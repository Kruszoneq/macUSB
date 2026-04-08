import Foundation

extension MontereyDownloadFlowModel {
    func startAssemblyWithHelper(
        request: DownloaderAssemblyRequestPayload
    ) async throws -> DownloaderAssemblyResultPayload {
        try await withCheckedThrowingContinuation { continuation in
            var didFinish = false
            let finish: (Result<DownloaderAssemblyResultPayload, Error>) -> Void = { result in
                guard !didFinish else { return }
                didFinish = true
                switch result {
                case let .success(payload):
                    continuation.resume(returning: payload)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            PrivilegedOperationClient.shared.startDownloaderAssembly(
                request: request,
                onEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.currentStage = .buildingInstaller
                        self.buildProgress = max(
                            self.buildProgress ?? 0,
                            min(max(event.percent, 0), 1)
                        )
                        self.buildStatusText = event.statusText
                        if let logLine = event.logLine, !logLine.isEmpty {
                            AppLogging.info(logLine, category: "Downloader")
                        }
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        self?.activeAssemblyWorkflowID = nil
                    }
                    finish(.success(result))
                },
                onStartError: { message in
                    finish(.failure(DownloadFailureReason.assemblyFailed(message)))
                },
                onStarted: { [weak self] workflowID in
                    Task { @MainActor [weak self] in
                        self?.activeAssemblyWorkflowID = workflowID
                    }
                }
            )
        }
    }
}
