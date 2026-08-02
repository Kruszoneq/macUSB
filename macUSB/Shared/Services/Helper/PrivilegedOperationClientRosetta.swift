import Foundation

extension PrivilegedOperationClient {
    func installRosetta(
        completion: @escaping (Result<RosettaInstallationResultPayload, Error>) -> Void
    ) {
        let stateLock = NSLock()
        var didFinish = false
        let finishOnce: (Result<RosettaInstallationResultPayload, Error>) -> Void = { result in
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

        proxy.installRosetta { data, error in
            if let error {
                finishOnce(.failure(error))
                return
            }
            guard let data else {
                finishOnce(.failure(NSError(
                    domain: "macUSB",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Helper nie zwrócił wyniku instalacji Rosetty."]
                )))
                return
            }

            do {
                let result = try HelperXPCCodec.decode(
                    RosettaInstallationResultPayload.self,
                    from: data as Data
                )
                finishOnce(.success(result))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }
}
