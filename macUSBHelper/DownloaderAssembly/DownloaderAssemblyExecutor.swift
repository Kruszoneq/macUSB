import Foundation
import Darwin

final class DownloaderAssemblyExecutor {
    let request: DownloaderAssemblyRequestPayload
    let workflowID: String
    let sendProgress: (DownloaderAssemblyProgressPayload) -> Void

    let stateQueue = DispatchQueue(label: "macUSB.helper.downloaderAssembly.state")
    var activeProcess: Process?
    var isCancelled = false
    var assemblyPackageName: String = "InstallAssistant.pkg"

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
        let outputDirectoryPath = URL(fileURLWithPath: request.outputDirectoryPath, isDirectory: true)
        let sessionRootDirectory = outputDirectoryPath.deletingLastPathComponent()
        let cleanupRequested = request.cleanupSessionFiles

        var flowSuccess = false
        var outputAppPath: String?
        var flowErrorMessage: String?

        do {
            try throwIfCancelled()
            emit(percent: 0.02, status: "Przygotowywanie aplikacji instalatora...")

            let packageURL = URL(fileURLWithPath: request.packagePath)
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                throw NSError(
                    domain: "macUSBHelper",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Nie znaleziono pakietu instalatora w sesji pobierania (\(packageURL.lastPathComponent))."]
                )
            }
            assemblyPackageName = packageURL.lastPathComponent

            try FileManager.default.createDirectory(at: outputDirectoryPath, withIntermediateDirectories: true)

            let assembledAppURL: URL
            if packageURL.pathExtension.caseInsensitiveCompare("dist") == .orderedSame {
                emit(percent: 0.10, status: "Instalowanie składników systemu...")
                assembledAppURL = try runLegacyDistributionAndLocateApp(
                    distributionURL: packageURL,
                    sessionRootDirectory: sessionRootDirectory,
                    patchLegacyDistribution: request.patchLegacyDistributionInDebug
                )
            } else if packageURL.pathExtension.caseInsensitiveCompare("dmg") == .orderedSame {
                guard isSierraAssemblyRequest else {
                    throw NSError(
                        domain: "macUSBHelper",
                        code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Obraz .dmg jest wspierany tylko dla assembly Sierra w downloaderze."]
                    )
                }
                emit(percent: 0.10, status: "Otwieranie obrazu instalatora...")
                assembledAppURL = try runSierraDiskImageAssemblyAndLocateApp(
                    diskImageURL: packageURL,
                    sessionRootDirectory: sessionRootDirectory
                )
            } else {
                emit(percent: 0.10, status: "Instalowanie składników systemu...")
                assembledAppURL = try runInstallerAndLocateApp(
                    packageURL: packageURL,
                    applyLegacyCompatibilityEnvironment: assemblyPackageName.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
                )
            }

            try throwIfCancelled()
            let finalDestinationURL = assembledAppURL
            try rewriteInstallerOwnershipToRequesterIfNeeded(installerAppURL: finalDestinationURL)
            emit(
                percent: 0.95,
                status: "Instalator gotowy",
                logLine: "assembly output-ready path=\(finalDestinationURL.path)"
            )

            if request.cleanupSessionFiles {
                emit(percent: 0.98, status: "Czyszczenie plików tymczasowych sesji")
            }

            emit(percent: 1.0, status: "Instalator przygotowany")
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

    var isSierraAssemblyRequest: Bool {
        let expected = request.expectedAppName.lowercased()
        return expected.contains("sierra")
    }
}
