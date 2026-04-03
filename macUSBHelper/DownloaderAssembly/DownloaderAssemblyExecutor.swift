import Foundation
import Darwin

final class DownloaderAssemblyExecutor {
    let request: DownloaderAssemblyRequestPayload
    let workflowID: String
    let sendProgress: (DownloaderAssemblyProgressPayload) -> Void

    let stateQueue = DispatchQueue(label: "macUSB.helper.downloaderAssembly.state")
    var activeProcess: Process?
    var isCancelled = false

    init(
        request: DownloaderAssemblyRequestPayload,
        workflowID: String,
        sendProgress: @escaping (DownloaderAssemblyProgressPayload) -> Void
    ) {
        self.request = request
        self.workflowID = workflowID
        self.sendProgress = sendProgress
    }

    func cancel() {
        stateQueue.sync {
            isCancelled = true
            guard let process = activeProcess, process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    func run() -> DownloaderAssemblyResultPayload {
        let outputDirectory = URL(fileURLWithPath: request.outputDirectoryPath, isDirectory: true)
        let sessionRootDirectory = outputDirectory.deletingLastPathComponent()
        let cleanupRequested = request.cleanupSessionFiles

        var flowSuccess = false
        var outputAppPath: String?
        var flowErrorMessage: String?

        do {
            try throwIfCancelled()
            emit(percent: 0.02, status: "Przygotowanie etapu budowania .app")

            let packageURL = URL(fileURLWithPath: request.packagePath)
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                throw NSError(
                    domain: "macUSBHelper",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Nie znaleziono InstallAssistant.pkg w sesji pobierania."]
                )
            }

            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            emit(percent: 0.10, status: "Instalacja pakietu InstallAssistant.pkg")
            let assembledAppURL = try runInstallerAndLocateApp(packageURL: packageURL)

            try throwIfCancelled()

            let destinationURL = outputDirectory.appendingPathComponent(request.expectedAppName, isDirectory: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            emit(
                percent: 0.88,
                status: "Kopiowanie instalatora .app do katalogu sesji",
                logLine: "assembly copy-to-session start source=\(assembledAppURL.path) destination=\(destinationURL.path)"
            )
            try runCommand(
                executable: "/usr/bin/ditto",
                arguments: [assembledAppURL.path, destinationURL.path]
            )
            emit(
                percent: 0.91,
                status: "Kopiowanie instalatora .app do katalogu sesji",
                logLine: "assembly copy-to-session success destination=\(destinationURL.path)"
            )

            emit(
                percent: 0.94,
                status: "Przenoszenie instalatora do katalogu docelowego",
                logLine: "assembly move-to-final start source=\(destinationURL.path) destination_dir=\(request.finalDestinationDirectoryPath)"
            )
            let finalDestinationURL = try moveInstallerToFinalDestination(from: destinationURL)
            emit(
                percent: 0.97,
                status: "Przenoszenie instalatora do katalogu docelowego",
                logLine: "assembly move-to-final success destination=\(finalDestinationURL.path)"
            )

            emit(percent: 0.975, status: "Finalizacja uprawnien instalatora")
            try normalizeOwnership(path: finalDestinationURL.path, requesterUID: request.requesterUID)

            if request.cleanupSessionFiles {
                emit(percent: 0.98, status: "Czyszczenie plików tymczasowych sesji")
            }

            emit(percent: 1.0, status: "Budowanie instalatora .app zakończone")
            flowSuccess = true
            outputAppPath = finalDestinationURL.path
        } catch {
            flowSuccess = false
            flowErrorMessage = (error as NSError).localizedDescription
        }

        var cleanupSucceeded = false
        var cleanupErrorMessage: String?
        if cleanupRequested {
            do {
                try cleanupSessionDirectory(sessionRootDirectory)
                cleanupSucceeded = true
            } catch {
                cleanupSucceeded = false
                cleanupErrorMessage = error.localizedDescription
            }
        }

        if !flowSuccess, let cleanupErrorMessage, cleanupRequested {
            flowErrorMessage = "\(flowErrorMessage ?? "Nieznany błąd"). Dodatkowo cleanup sesji nie powiódł się: \(cleanupErrorMessage)"
        }

        return DownloaderAssemblyResultPayload(
            workflowID: workflowID,
            success: flowSuccess,
            outputAppPath: outputAppPath,
            errorMessage: flowErrorMessage,
            cleanupRequested: cleanupRequested,
            cleanupSucceeded: cleanupSucceeded,
            cleanupErrorMessage: cleanupErrorMessage
        )
    }

    private func normalizeOwnership(path: String, requesterUID: UInt32) throws {
        guard requesterUID > 0 else { return }
        do {
            try runCommand(
                executable: "/usr/sbin/chown",
                arguments: ["-R", "\(requesterUID)", path]
            )
            emit(
                percent: nil,
                status: "Finalizacja uprawnien instalatora",
                logLine: "assembly ownership normalize success uid=\(requesterUID) path=\(path)"
            )
        } catch {
            emit(
                percent: nil,
                status: "Finalizacja uprawnien instalatora",
                logLine: "assembly ownership normalize failed uid=\(requesterUID) path=\(path) error=\(error.localizedDescription)"
            )
            throw NSError(
                domain: "macUSBHelper",
                code: 550,
                userInfo: [NSLocalizedDescriptionKey: "Nie udalo sie ustawic wlasciciela instalatora na domyslnego uzytkownika: \(error.localizedDescription)"]
            )
        }
    }
}
