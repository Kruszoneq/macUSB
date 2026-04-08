import Foundation
import Darwin

final class PrivilegedHelperService: NSObject, PrivilegedHelperToolXPCProtocol {
    weak var connection: NSXPCConnection?

    private var activeWorkflowID: String?
    private var activeExecutor: HelperWorkflowExecutor?
    private var activeDownloaderAssemblyID: String?
    private var activeDownloaderAssemblyExecutor: DownloaderAssemblyExecutor?
    private let queue = DispatchQueue(label: "macUSB.helper.service")

    func startWorkflow(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void) {
        queue.async {
            guard self.activeExecutor == nil, self.activeDownloaderAssemblyExecutor == nil else {
                let error = NSError(
                    domain: "macUSBHelper",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Helper realizuje już inne zadanie."]
                )
                reply(nil, error)
                return
            }

            let request: HelperWorkflowRequestPayload
            do {
                request = try HelperXPCCodec.decode(HelperWorkflowRequestPayload.self, from: requestData as Data)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowe żądanie helpera: \(error.localizedDescription)"]
                )
                reply(nil, err)
                return
            }

            let workflowID = UUID().uuidString
            let executor = HelperWorkflowExecutor(
                request: request,
                workflowID: workflowID,
                sendEvent: { [weak self] event in
                    self?.sendProgress(event)
                }
            )

            self.activeWorkflowID = workflowID
            self.activeExecutor = executor
            reply(workflowID as NSString, nil)

            DispatchQueue.global(qos: .userInitiated).async {
                let result = executor.run()
                self.queue.async {
                    self.sendResult(result)
                    self.activeWorkflowID = nil
                    self.activeExecutor = nil
                }
            }
        }
    }

    func cancelWorkflow(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void) {
        queue.async {
            guard self.activeWorkflowID == workflowID, let executor = self.activeExecutor else {
                reply(false, nil)
                return
            }
            executor.cancel()
            reply(true, nil)
        }
    }

    func startDownloaderAssembly(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void) {
        queue.async {
            guard self.activeExecutor == nil, self.activeDownloaderAssemblyExecutor == nil else {
                let error = NSError(
                    domain: "macUSBHelper",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Helper realizuje już inne zadanie."]
                )
                reply(nil, error)
                return
            }

            let request: DownloaderAssemblyRequestPayload
            do {
                request = try HelperXPCCodec.decode(DownloaderAssemblyRequestPayload.self, from: requestData as Data)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowe żądanie assembly downloadera: \(error.localizedDescription)"]
                )
                reply(nil, err)
                return
            }

            let workflowID = UUID().uuidString
            let executor = DownloaderAssemblyExecutor(
                request: request,
                workflowID: workflowID,
                sendProgress: { [weak self] event in
                    self?.sendDownloaderAssemblyProgress(event)
                }
            )

            self.activeDownloaderAssemblyID = workflowID
            self.activeDownloaderAssemblyExecutor = executor
            reply(workflowID as NSString, nil)

            DispatchQueue.global(qos: .userInitiated).async {
                let result = executor.run()
                self.queue.async {
                    self.sendDownloaderAssemblyResult(result)
                    self.activeDownloaderAssemblyID = nil
                    self.activeDownloaderAssemblyExecutor = nil
                }
            }
        }
    }

    func cancelDownloaderAssembly(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void) {
        queue.async {
            guard self.activeDownloaderAssemblyID == workflowID,
                  let executor = self.activeDownloaderAssemblyExecutor
            else {
                reply(false, nil)
                return
            }

            executor.cancel()
            reply(true, nil)
        }
    }

    func cleanupDownloaderSession(_ requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void) {
        queue.async {
            guard self.activeExecutor == nil, self.activeDownloaderAssemblyExecutor == nil else {
                let error = NSError(
                    domain: "macUSBHelper",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Helper realizuje już inne zadanie."]
                )
                reply(nil, error)
                return
            }

            let request: DownloaderCleanupRequestPayload
            do {
                request = try HelperXPCCodec.decode(DownloaderCleanupRequestPayload.self, from: requestData as Data)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowe żądanie cleanupu downloadera: \(error.localizedDescription)"]
                )
                reply(nil, err)
                return
            }

            let sessionRootURL = URL(fileURLWithPath: request.sessionRootPath, isDirectory: true)
            let result: DownloaderCleanupResultPayload
            do {
                if FileManager.default.fileExists(atPath: sessionRootURL.path) {
                    try FileManager.default.removeItem(at: sessionRootURL)
                }
                if FileManager.default.fileExists(atPath: sessionRootURL.path) {
                    throw NSError(
                        domain: "macUSBHelper",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Katalog sesji nadal istnieje po cleanup: \(sessionRootURL.path)"]
                    )
                }
                result = DownloaderCleanupResultPayload(success: true, errorMessage: nil)
            } catch {
                result = DownloaderCleanupResultPayload(success: false, errorMessage: error.localizedDescription)
            }

            do {
                let encoded = try HelperXPCCodec.encode(result)
                reply(encoded as NSData, nil)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Nie udało się zakodować wyniku cleanupu: \(error.localizedDescription)"]
                )
                reply(nil, err)
            }
        }
    }

    func queryHealth(_ reply: @escaping (Bool, NSString) -> Void) {
        let uid = getuid()
        let euid = geteuid()
        let pid = getpid()
        reply(true, "Helper odpowiada poprawnie (uid=\(uid), euid=\(euid), pid=\(pid))" as NSString)
    }

    private func sendProgress(_ event: HelperProgressEventPayload) {
        guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PrivilegedHelperClientXPCProtocol else {
            return
        }

        guard let encoded = try? HelperXPCCodec.encode(event) else {
            return
        }
        client.receiveProgressEvent(encoded as NSData)
    }

    private func sendResult(_ result: HelperWorkflowResultPayload) {
        guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PrivilegedHelperClientXPCProtocol else {
            return
        }

        guard let encoded = try? HelperXPCCodec.encode(result) else {
            return
        }
        client.finishWorkflow(encoded as NSData)
    }

    private func sendDownloaderAssemblyProgress(_ event: DownloaderAssemblyProgressPayload) {
        guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PrivilegedHelperClientXPCProtocol else {
            return
        }

        guard let encoded = try? HelperXPCCodec.encode(event) else {
            return
        }
        client.receiveDownloaderAssemblyProgress(encoded as NSData)
    }

    private func sendDownloaderAssemblyResult(_ result: DownloaderAssemblyResultPayload) {
        guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PrivilegedHelperClientXPCProtocol else {
            return
        }

        guard let encoded = try? HelperXPCCodec.encode(result) else {
            return
        }
        client.finishDownloaderAssembly(encoded as NSData)
    }
}
