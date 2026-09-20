import Foundation

extension MontereyDownloadFlowModel {
    func runDiskImageCreation() async throws -> MacOSDiskImageCreationOutcome {
        guard activeDiskImageConfiguration.isEnabled,
              let preflightPlan = activeDiskImagePreflightPlan
        else {
            throw MacOSDiskImageCreationError.missingConfiguration
        }
        guard let installerURL = finalInstallerAppURL,
              FileManager.default.fileExists(atPath: installerURL.path)
        else {
            throw MacOSDiskImageCreationError.missingInstaller
        }
        guard let outputDirectoryURL = activeSessionOutputURL else {
            throw MacOSDiskImageCreationError.missingSessionOutput
        }

        currentStage = .creatingDiskImage
        diskImageStageStatus = .preparing

        let fileManager = FileManager.default
        let stagingDirectoryURL = outputDirectoryURL
            .appendingPathComponent("DiskImageContents", isDirectory: true)
        let stagedInstallerURL = stagingDirectoryURL
            .appendingPathComponent(installerURL.lastPathComponent, isDirectory: true)
        let temporaryImageURL = preflightPlan.destinationDirectoryURL
            .appendingPathComponent(".macusb-dmg-\(UUID().uuidString.lowercased()).dmg")
        var installerWasStaged = false

        AppLogging.info(
            "Tworzenie obrazu DMG: rozpoczęto; instalator=\(installerURL.path), plik docelowy=\(preflightPlan.destinationURL.path).",
            category: "Downloader"
        )

        do {
            guard fileManager.fileExists(atPath: preflightPlan.destinationDirectoryURL.path),
                  fileManager.isWritableFile(atPath: preflightPlan.destinationDirectoryURL.path)
            else {
                throw MacOSDiskImageCreationError.destinationUnavailable
            }

            if fileManager.fileExists(atPath: stagingDirectoryURL.path) {
                try fileManager.removeItem(at: stagingDirectoryURL)
            }
            try fileManager.createDirectory(
                at: stagingDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: installerURL, to: stagedInstallerURL)
            installerWasStaged = true
            finalInstallerAppURL = stagedInstallerURL

            diskImageStageStatus = .creating
            let processResult = try await diskImageProcessRunner.run(arguments: [
                "create",
                "-srcfolder", stagingDirectoryURL.path,
                "-format", "UDRO",
                "-volname", preflightPlan.volumeName,
                temporaryImageURL.path
            ])
            try Task.checkCancellation()

            let diagnostic = [processResult.standardOutput, processResult.standardError]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard processResult.terminationStatus == 0 else {
                throw MacOSDiskImageCreationError.processFailed(
                    diagnostic.isEmpty
                        ? "hdiutil exited with status \(processResult.terminationStatus)"
                        : diagnostic
                )
            }

            let attributes = try fileManager.attributesOfItem(atPath: temporaryImageURL.path)
            guard let fileSize = attributes[.size] as? NSNumber,
                  fileSize.int64Value > 0
            else {
                throw MacOSDiskImageCreationError.invalidOutput
            }

            let destinationURL: URL
            if fileManager.fileExists(atPath: preflightPlan.destinationURL.path) {
                destinationURL = MacOSDiskImageNamingPolicy.firstAvailableSuffixedURL(
                    in: preflightPlan.destinationDirectoryURL,
                    preferredFileName: preflightPlan.preferredFileName,
                    fileManager: fileManager
                )
            } else {
                destinationURL = preflightPlan.destinationURL
            }
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw MacOSDiskImageCreationError.destinationCollision
            }
            try fileManager.moveItem(at: temporaryImageURL, to: destinationURL)
            finalDiskImageURL = destinationURL

            diskImageStageStatus = .removingSource
            do {
                try fileManager.removeItem(at: stagedInstallerURL)
                try? fileManager.removeItem(at: stagingDirectoryURL)
                finalInstallerAppURL = nil
                retainedSourceInstallerURL = nil
                diskImageStageStatus = .completed
                completedStages.insert(.creatingDiskImage)
                AppLogging.info(
                    "Tworzenie obrazu DMG: zakończono pomyślnie; obraz=\(destinationURL.path).",
                    category: "Downloader"
                )
                return .success(diskImageURL: destinationURL)
            } catch {
                let retainedURL = try restoreStagedInstaller(
                    from: stagedInstallerURL,
                    preferredDestinationURL: installerURL
                )
                finalInstallerAppURL = retainedURL
                retainedSourceInstallerURL = retainedURL
                diskImageSourceRemovalWarning = true
                diskImageStageStatus = .completed
                completedStages.insert(.creatingDiskImage)
                AppLogging.error(
                    "Tworzenie obrazu DMG: zakończono z błędem usuwania instalatora źródłowego; obraz=\(destinationURL.path), zachowany instalator=\(retainedURL.path), szczegóły=\(error.localizedDescription)",
                    category: "Downloader"
                )
                return .partialSuccess(
                    diskImageURL: destinationURL,
                    retainedInstallerURL: retainedURL
                )
            }
        } catch {
            let creationError = error
            if fileManager.fileExists(atPath: temporaryImageURL.path) {
                try? fileManager.removeItem(at: temporaryImageURL)
            }
            if installerWasStaged,
               fileManager.fileExists(atPath: stagedInstallerURL.path) {
                do {
                    let restoredURL = try restoreStagedInstaller(
                        from: stagedInstallerURL,
                        preferredDestinationURL: installerURL
                    )
                    finalInstallerAppURL = restoredURL
                } catch {
                    AppLogging.error(
                        "Tworzenie obrazu DMG: zakończono błędem; nie udało się przywrócić instalatora źródłowego: \(error.localizedDescription)",
                        category: "Downloader"
                    )
                    throw MacOSDiskImageCreationError.sourceRestoreFailed(
                        error.localizedDescription
                    )
                }
            }
            if creationError is CancellationError || Task.isCancelled {
                AppLogging.info(
                    "Tworzenie obrazu DMG: anulowano.",
                    category: "Downloader"
                )
                throw CancellationError()
            }
            AppLogging.error(
                "Tworzenie obrazu DMG: zakończono błędem: \(diskImageTechnicalDescription(for: creationError))",
                category: "Downloader"
            )
            throw creationError
        }
    }

    private func restoreStagedInstaller(
        from stagedInstallerURL: URL,
        preferredDestinationURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL: URL
        if fileManager.fileExists(atPath: preferredDestinationURL.path) {
            destinationURL = uniqueCollisionSafeURL(
                in: preferredDestinationURL.deletingLastPathComponent(),
                preferredFileName: preferredDestinationURL.lastPathComponent
            )
        } else {
            destinationURL = preferredDestinationURL
        }
        try fileManager.moveItem(at: stagedInstallerURL, to: destinationURL)
        try? fileManager.removeItem(at: stagedInstallerURL.deletingLastPathComponent())
        return destinationURL
    }
}
