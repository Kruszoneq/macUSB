import Foundation

extension MontereyDownloadFlowModel {
    func runLegacyFileStepWithProgress(
        statusText: String,
        progressStart: Double,
        progressEnd: Double,
        stepName: String,
        operation: @escaping () throws -> Void
    ) async throws {
        AppLogging.info("Legacy assembly: \(stepName) start", category: "Downloader")
        buildStatusText = statusText
        buildProgress = max(buildProgress ?? progressStart, progressStart)

        let progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentProgress = max(self.buildProgress ?? progressStart, progressStart)
            while !Task.isCancelled {
                currentProgress = min(progressEnd - 0.01, currentProgress + 0.01)
                self.buildProgress = currentProgress
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        do {
            try await runBlockingOperation(operation)
            progressTask.cancel()
            buildProgress = max(buildProgress ?? progressStart, progressEnd)
            AppLogging.info("Legacy assembly: \(stepName) success", category: "Downloader")
        } catch {
            progressTask.cancel()
            let message = error.localizedDescription
            AppLogging.error("Legacy assembly: \(stepName) failed: \(message)", category: "Downloader")
            if error is DownloadFailureReason {
                throw error
            }
            throw DownloadFailureReason.assemblyFailed(message)
        }
    }

    func runCommandWithBuildProgress(
        executable: String,
        arguments: [String],
        statusText: String,
        progressStart: Double,
        progressEnd: Double,
        stepName: String
    ) async throws -> String {
        AppLogging.info(
            "Legacy assembly: \(stepName) start executable=\(URL(fileURLWithPath: executable).lastPathComponent) args=\(arguments.joined(separator: " "))",
            category: "Downloader"
        )
        buildStatusText = statusText
        buildProgress = max(buildProgress ?? progressStart, progressStart)

        let progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentProgress = max(self.buildProgress ?? progressStart, progressStart)
            while !Task.isCancelled {
                currentProgress = min(progressEnd - 0.01, currentProgress + 0.008)
                self.buildProgress = currentProgress
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        do {
            let output = try await runProcessAndCaptureOutputOffMain(
                executable: executable,
                arguments: arguments
            )
            progressTask.cancel()
            buildProgress = max(buildProgress ?? progressStart, progressEnd)
            AppLogging.info("Legacy assembly: \(stepName) success", category: "Downloader")
            return output
        } catch {
            progressTask.cancel()
            throw error
        }
    }
}
