import Foundation

final class PrivilegedOperationClient: NSObject {
    static let shared = PrivilegedOperationClient()

    typealias EventHandler = (HelperProgressEventPayload) -> Void
    typealias CompletionHandler = (HelperWorkflowResultPayload) -> Void

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var eventHandlers: [String: EventHandler] = [:]
    private var completionHandlers: [String: CompletionHandler] = [:]
    private let startReplyTimeout: TimeInterval = 10
    private let healthReplyTimeout: TimeInterval = 5

    private override init() {
        super.init()
    }

    func startWorkflow(
        request: HelperWorkflowRequestPayload,
        onEvent: @escaping EventHandler,
        onCompletion: @escaping CompletionHandler,
        onStartError: @escaping (String) -> Void,
        onStarted: @escaping (String) -> Void
    ) {
        let stateLock = NSLock()
        var didFinish = false
        let finishOnce: (@escaping () -> Void) -> Void = { action in
            stateLock.lock()
            let shouldRun = !didFinish
            if shouldRun {
                didFinish = true
            }
            stateLock.unlock()
            guard shouldRun else { return }
            action()
        }

        var timeoutWorkItem: DispatchWorkItem?
        let failStart: (String) -> Void = { [weak self] message in
            DispatchQueue.main.async {
                timeoutWorkItem?.cancel()
                self?.resetConnection()
                finishOnce {
                    onStartError(message)
                }
            }
        }

        guard let proxy = helperProxy(onError: { message in
            failStart(message)
        }) else {
            failStart("Nie udało się uzyskać połączenia XPC z helperem.")
            return
        }

        let requestData: Data
        do {
            requestData = try HelperXPCCodec.encode(request)
        } catch {
            failStart("Nie udało się zakodować żądania helpera: \(error.localizedDescription)")
            return
        }

        timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.resetConnection()
            DispatchQueue.main.async {
                finishOnce {
                    onStartError("Przekroczono czas oczekiwania na odpowiedź helpera XPC.")
                }
            }
        }
        if let timeoutWorkItem {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + startReplyTimeout,
                execute: timeoutWorkItem
            )
        }

        proxy.startWorkflow(requestData as NSData) { [weak self] workflowID, error in
            DispatchQueue.main.async {
                finishOnce {
                    timeoutWorkItem?.cancel()

                    if let error {
                        onStartError(error.localizedDescription)
                        return
                    }
                    guard let workflowID = workflowID as String?, !workflowID.isEmpty else {
                        onStartError("Helper nie zwrócił identyfikatora zadania.")
                        return
                    }

                    self?.lock.lock()
                    self?.eventHandlers[workflowID] = onEvent
                    self?.completionHandlers[workflowID] = onCompletion
                    self?.lock.unlock()

                    onStarted(workflowID)
                }
            }
        }
    }

    func cancelWorkflow(_ workflowID: String, completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = helperProxy(onError: { message in
            DispatchQueue.main.async {
                completion(false, message)
            }
        }) else {
            return
        }

        proxy.cancelWorkflow(workflowID) { cancelled, error in
            DispatchQueue.main.async {
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    completion(cancelled, nil)
                }
            }
        }
    }

    func queryHealth(completion: @escaping (Bool, String) -> Void) {
        queryHealth(withTimeout: healthReplyTimeout, completion: completion)
    }

    func queryHealth(withTimeout timeout: TimeInterval, completion: @escaping (Bool, String) -> Void) {
        let stateLock = NSLock()
        var didFinish = false
        let finishOnce: (_ ok: Bool, _ details: String) -> Void = { ok, details in
            stateLock.lock()
            let shouldRun = !didFinish
            if shouldRun {
                didFinish = true
            }
            stateLock.unlock()
            guard shouldRun else { return }
            completion(ok, details)
        }

        var timeoutWorkItem: DispatchWorkItem?
        let failHealth: (String) -> Void = { [weak self] message in
            DispatchQueue.main.async {
                timeoutWorkItem?.cancel()
                self?.resetConnection()
                finishOnce(false, message)
            }
        }

        guard let proxy = helperProxy(onError: { _ in
            failHealth("Brak połączenia XPC z helperem")
        }) else {
            failHealth("Brak połączenia XPC z helperem")
            return
        }

        timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.resetConnection()
            DispatchQueue.main.async {
                finishOnce(false, "Timeout połączenia XPC z helperem")
            }
        }
        if let timeoutWorkItem {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )
        }

        proxy.queryHealth { ok, details in
            DispatchQueue.main.async {
                timeoutWorkItem?.cancel()
                finishOnce(ok, details as String)
            }
        }
    }

    func clearHandlers(for workflowID: String) {
        lock.lock()
        eventHandlers.removeValue(forKey: workflowID)
        completionHandlers.removeValue(forKey: workflowID)
        lock.unlock()
    }

    func resetConnectionForRecovery() {
        resetConnection()
    }

    private func helperProxy(onError: @escaping (String) -> Void) -> PrivilegedHelperToolXPCProtocol? {
        let connection = ensureConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async {
                onError("Błąd połączenia z helperem: \(error.localizedDescription)")
            }
        }
        guard let typedProxy = proxy as? PrivilegedHelperToolXPCProtocol else {
            DispatchQueue.main.async {
                onError("Nie udało się utworzyć proxy XPC helpera.")
            }
            return nil
        }
        return typedProxy
    }

    private func ensureConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return connection
        }

        let newConnection = NSXPCConnection(
            machServiceName: HelperServiceManager.machServiceName,
            options: .privileged
        )
        newConnection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperToolXPCProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperClientXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in
            self?.handleConnectionInvalidation("Połączenie z helperem zostało unieważnione.")
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.handleConnectionInvalidation("Połączenie z helperem zostało przerwane.")
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func resetConnection() {
        lock.lock()
        let existingConnection = connection
        connection = nil
        lock.unlock()
        existingConnection?.invalidate()
    }

    private func handleConnectionInvalidation(_ message: String) {
        lock.lock()
        let completionSnapshot = completionHandlers
        eventHandlers.removeAll()
        completionHandlers.removeAll()
        connection = nil
        lock.unlock()

        DispatchQueue.main.async {
            for (workflowID, handler) in completionSnapshot {
                handler(
                    HelperWorkflowResultPayload(
                        workflowID: workflowID,
                        success: false,
                        failedStage: "xpc_connection",
                        errorCode: nil,
                        errorMessage: message,
                        isUserCancelled: false
                    )
                )
            }
        }
    }
}

extension PrivilegedOperationClient: PrivilegedHelperClientXPCProtocol {
    func receiveProgressEvent(_ eventData: NSData) {
        let event: HelperProgressEventPayload
        do {
            event = try HelperXPCCodec.decode(HelperProgressEventPayload.self, from: eventData as Data)
        } catch {
            AppLogging.error("Nie udało się zdekodować zdarzenia helpera: \(error.localizedDescription)", category: "HelperLiveLog")
            return
        }

        if let logLine = event.logLine, !logLine.isEmpty {
            AppLogging.info(logLine, category: "HelperLiveLog")
        }

        lock.lock()
        let handler = eventHandlers[event.workflowID]
        lock.unlock()

        if let handler {
            DispatchQueue.main.async {
                handler(event)
            }
        }
    }

    func finishWorkflow(_ resultData: NSData) {
        let result: HelperWorkflowResultPayload
        do {
            result = try HelperXPCCodec.decode(HelperWorkflowResultPayload.self, from: resultData as Data)
        } catch {
            AppLogging.error("Nie udało się zdekodować wyniku helpera: \(error.localizedDescription)", category: "HelperLiveLog")
            return
        }

        lock.lock()
        let completion = completionHandlers[result.workflowID]
        eventHandlers.removeValue(forKey: result.workflowID)
        completionHandlers.removeValue(forKey: result.workflowID)
        lock.unlock()

        if let completion {
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
