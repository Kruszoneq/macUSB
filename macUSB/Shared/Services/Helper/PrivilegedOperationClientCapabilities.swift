import Foundation

extension PrivilegedOperationClient {
    static let windowsMacUSBootCapability = "windows.macusboot.v1"

    func queryCapabilities(completion: @escaping (Result<Set<String>, Error>) -> Void) {
        let stateLock = NSLock()
        var didFinish = false
        let finishOnce: (Result<Set<String>, Error>) -> Void = { result in
            stateLock.lock()
            let shouldFinish = !didFinish
            didFinish = true
            stateLock.unlock()
            guard shouldFinish else { return }
            DispatchQueue.main.async {
                completion(result)
            }
        }

        guard let proxy = helperProxy(presentsTrustFailureAlert: true, onError: { message in
            finishOnce(.failure(NSError(
                domain: "macUSB",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )))
        }) else {
            finishOnce(.failure(NSError(
                domain: "macUSB",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie udało się uzyskać połączenia XPC z helperem.")]
            )))
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.resetConnectionForRecovery()
            finishOnce(.failure(NSError(
                domain: "macUSB",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Przekroczono czas oczekiwania na odpowiedź helpera XPC.")]
            )))
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5, execute: timeout)

        proxy.queryCapabilities { data, error in
            timeout.cancel()
            if let error {
                finishOnce(.failure(error))
                return
            }
            guard let data else {
                finishOnce(.failure(NSError(
                    domain: "macUSB",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Helper nie zwrócił listy capability."]
                )))
                return
            }

            do {
                let payload = try HelperXPCCodec.decode(HelperCapabilitiesPayload.self, from: data as Data)
                finishOnce(.success(Set(payload.capabilities)))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }
}
