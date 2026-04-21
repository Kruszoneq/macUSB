import Foundation

enum HelperExecutionError: Error {
    case cancelled
    case failed(stage: String, exitCode: Int32, description: String)
    case invalidRequest(String)
}

struct WorkflowStage {
    let key: String
    let titleKey: String
    let statusKey: String
    let startPercent: Double
    let endPercent: Double
    let executable: String
    let arguments: [String]
    let parseToolPercent: Bool
}

struct PreparedWorkflowContext {
    let sourcePath: String
    let postInstallSourceAppPath: String?
}

extension HelperWorkflowExecutor {
    func prepareWorkflowContext() throws -> PreparedWorkflowContext {
        let stageKey = "prepare_source"
        let stageTitleKey = HelperWorkflowLocalizationKeys.prepareSourceTitle
        let statusKey = HelperWorkflowLocalizationKeys.prepareSourceStatus

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: 0,
            statusKey: statusKey
        )

        try ensureTempWorkDirectoryExists()

        let context: PreparedWorkflowContext
        switch request.workflowKind {
        case .legacyRestore:
            let sourceESD = URL(fileURLWithPath: request.sourceAppPath)
                .appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
            guard fileManager.fileExists(atPath: sourceESD.path) else {
                throw HelperExecutionError.invalidRequest("Nie znaleziono pliku InstallESD.dmg.")
            }

            let stagedESD = URL(fileURLWithPath: request.tempWorkPath).appendingPathComponent("InstallESD.dmg")
            try copyReplacingItem(at: sourceESD, to: stagedESD)
            context = PreparedWorkflowContext(sourcePath: stagedESD.path, postInstallSourceAppPath: nil)

        case .mavericks:
            let sourceImagePath = request.originalImagePath ?? request.sourceAppPath
            guard fileManager.fileExists(atPath: sourceImagePath) else {
                throw HelperExecutionError.invalidRequest("Nie znaleziono źródłowego pliku obrazu.")
            }

            let sourceImage = URL(fileURLWithPath: sourceImagePath)
            let stagedImage = URL(fileURLWithPath: request.tempWorkPath).appendingPathComponent("InstallESD.dmg")
            try copyReplacingItem(at: sourceImage, to: stagedImage)
            context = PreparedWorkflowContext(sourcePath: stagedImage.path, postInstallSourceAppPath: nil)

        case .ppc:
            let mountedVolumeSource = URL(fileURLWithPath: request.sourceAppPath)
                .deletingLastPathComponent()
                .path
            let mountedSourceAvailable = mountedVolumeSource.hasPrefix("/Volumes/") &&
                fileManager.fileExists(atPath: mountedVolumeSource)

            if let imagePath = request.originalImagePath, fileManager.fileExists(atPath: imagePath) {
                let imageURL = URL(fileURLWithPath: imagePath)
                let sourceExt = imageURL.pathExtension.lowercased()

                if (sourceExt == "iso" || sourceExt == "cdr"), mountedSourceAvailable {
                    let message = "PPC helper strategy: asr restore from mounted source (ISO/CDR) -> /Volumes/PPC"
                    emitProgress(
                        stageKey: stageKey,
                        titleKey: stageTitleKey,
                        percent: latestPercent,
                        statusKey: statusKey,
                        logLine: message,
                        shouldAdvancePercent: false
                    )
                    context = PreparedWorkflowContext(sourcePath: mountedVolumeSource, postInstallSourceAppPath: nil)
                } else {
                    let stagedImageURL = URL(fileURLWithPath: request.tempWorkPath)
                        .appendingPathComponent("PPC_\(imageURL.lastPathComponent)")
                    try copyReplacingItem(at: imageURL, to: stagedImageURL)
                    let message = "PPC helper strategy: asr restore from staged image -> /Volumes/PPC"
                    emitProgress(
                        stageKey: stageKey,
                        titleKey: stageTitleKey,
                        percent: latestPercent,
                        statusKey: statusKey,
                        logLine: message,
                        shouldAdvancePercent: false
                    )
                    context = PreparedWorkflowContext(sourcePath: stagedImageURL.path, postInstallSourceAppPath: nil)
                }
            } else if mountedSourceAvailable {
                let message = "PPC helper strategy: asr restore from mounted source fallback -> /Volumes/PPC"
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: message,
                    shouldAdvancePercent: false
                )
                context = PreparedWorkflowContext(sourcePath: mountedVolumeSource, postInstallSourceAppPath: nil)
            } else {
                throw HelperExecutionError.invalidRequest("Nie znaleziono źródła PPC do przywracania.")
            }

        case .standard:
            let sourceAppURL = URL(fileURLWithPath: request.sourceAppPath)
            var effectiveAppURL = sourceAppURL
            let sourceIsMountedVolume = request.sourceAppPath.hasPrefix("/Volumes/")

            if request.isSierra {
                let destinationAppURL = URL(fileURLWithPath: request.tempWorkPath)
                    .appendingPathComponent(sourceAppURL.lastPathComponent)
                try copyReplacingItem(at: sourceAppURL, to: destinationAppURL)

                try runSimpleCommand(
                    executable: "/usr/bin/plutil",
                    arguments: ["-replace", "CFBundleShortVersionString", "-string", "12.6.03", destinationAppURL.appendingPathComponent("Contents/Info.plist").path],
                    stageKey: stageKey,
                    stageTitleKey: stageTitleKey,
                    statusKey: statusKey
                )
                try runSimpleCommand(
                    executable: "/usr/bin/xattr",
                    arguments: ["-dr", "com.apple.quarantine", destinationAppURL.path],
                    stageKey: stageKey,
                    stageTitleKey: stageTitleKey,
                    statusKey: statusKey
                )
                try runSimpleCommand(
                    executable: "/usr/bin/codesign",
                    arguments: ["-s", "-", "-f", destinationAppURL.appendingPathComponent("Contents/Resources/createinstallmedia").path],
                    stageKey: stageKey,
                    stageTitleKey: stageTitleKey,
                    statusKey: statusKey
                )

                effectiveAppURL = destinationAppURL
            } else if sourceIsMountedVolume || request.isCatalina || request.needsCodesign {
                let destinationAppURL = URL(fileURLWithPath: request.tempWorkPath)
                    .appendingPathComponent(sourceAppURL.lastPathComponent)
                try copyReplacingItem(at: sourceAppURL, to: destinationAppURL)

                if request.isCatalina || request.needsCodesign {
                    try performLocalCodesign(
                        on: destinationAppURL,
                        stageKey: stageKey,
                        stageTitleKey: stageTitleKey,
                        statusKey: statusKey
                    )
                }

                effectiveAppURL = destinationAppURL
            }

            let postInstallSourcePath = request.isCatalina
                ? URL(fileURLWithPath: request.sourceAppPath).resolvingSymlinksInPath().path
                : nil

            context = PreparedWorkflowContext(
                sourcePath: effectiveAppURL.path,
                postInstallSourceAppPath: postInstallSourcePath
            )

        case .linux:
            context = try prepareLinuxWorkflowContext()
        }

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: 10,
            statusKey: statusKey
        )

        return context
    }
    func buildStages(using context: PreparedWorkflowContext) throws -> [WorkflowStage] {
        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)
        let formatTargetWholeDisk = resolvePartitionTargetWholeDisk(
            fromRequestedBSDName: request.targetBSDName,
            targetVolumePath: request.targetVolumePath,
            fallbackWholeDisk: wholeDisk
        )
        emitProgress(
            stageKey: "prepare_source",
            titleKey: HelperWorkflowLocalizationKeys.prepareSourceTitle,
            percent: latestPercent,
            statusKey: HelperWorkflowLocalizationKeys.prepareSourceStatus,
            logLine: "Format target resolution: requested=\(request.targetBSDName), fallbackWhole=\(wholeDisk), resolvedWhole=\(formatTargetWholeDisk), targetVolumePath=\(request.targetVolumePath)",
            shouldAdvancePercent: false
        )
        let rawTargetPath = request.targetVolumePath
        var effectiveTargetPath = rawTargetPath

        var stages: [WorkflowStage] = []

        if request.workflowKind != .ppc && request.needsPreformat {
            stages.append(
                WorkflowStage(
                    key: "preformat",
                    titleKey: HelperWorkflowLocalizationKeys.preformatTitle,
                    statusKey: HelperWorkflowLocalizationKeys.preformatStatus,
                    startPercent: 10,
                    endPercent: 30,
                    executable: "/usr/sbin/diskutil",
                    arguments: ["partitionDisk", "/dev/\(formatTargetWholeDisk)", "GPT", "HFS+", request.targetLabel, "100%"],
                    parseToolPercent: false
                )
            )
            effectiveTargetPath = "/Volumes/\(request.targetLabel)"
        }

        switch request.workflowKind {
        case .legacyRestore:
            stages.append(
                WorkflowStage(
                    key: "imagescan",
                    titleKey: HelperWorkflowLocalizationKeys.imagescanTitle,
                    statusKey: HelperWorkflowLocalizationKeys.imagescanStatus,
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.needsPreformat ? 50 : 35,
                    executable: "/usr/sbin/asr",
                    arguments: ["imagescan", "--source", context.sourcePath],
                    parseToolPercent: true
                )
            )
            stages.append(
                WorkflowStage(
                    key: "restore",
                    titleKey: HelperWorkflowLocalizationKeys.restoreTitle,
                    statusKey: HelperWorkflowLocalizationKeys.restoreStatus,
                    startPercent: request.needsPreformat ? 50 : 35,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", context.sourcePath, "--target", effectiveTargetPath, "--erase", "--noprompt", "--noverify"],
                    parseToolPercent: true
                )
            )

        case .mavericks:
            stages.append(
                WorkflowStage(
                    key: "imagescan",
                    titleKey: HelperWorkflowLocalizationKeys.imagescanTitle,
                    statusKey: HelperWorkflowLocalizationKeys.imagescanStatus,
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.needsPreformat ? 50 : 35,
                    executable: "/usr/sbin/asr",
                    arguments: ["imagescan", "--source", context.sourcePath],
                    parseToolPercent: true
                )
            )
            stages.append(
                WorkflowStage(
                    key: "restore",
                    titleKey: HelperWorkflowLocalizationKeys.restoreTitle,
                    statusKey: HelperWorkflowLocalizationKeys.restoreStatus,
                    startPercent: request.needsPreformat ? 50 : 35,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", context.sourcePath, "--target", effectiveTargetPath, "--erase", "--noprompt", "--noverify"],
                    parseToolPercent: true
                )
            )

        case .ppc:
            stages.append(
                WorkflowStage(
                    key: "ppc_format",
                    titleKey: HelperWorkflowLocalizationKeys.ppcFormatTitle,
                    statusKey: HelperWorkflowLocalizationKeys.ppcFormatStatus,
                    startPercent: 10,
                    endPercent: 25,
                    executable: "/usr/sbin/diskutil",
                    arguments: ["partitionDisk", "/dev/\(formatTargetWholeDisk)", "APM", "HFS+", "PPC", "100%"],
                    parseToolPercent: false
                )
            )

            let ppcRestoreSource = resolvePPCSourceArgument(from: context.sourcePath)
            stages.append(
                WorkflowStage(
                    key: "ppc_restore",
                    titleKey: HelperWorkflowLocalizationKeys.ppcRestoreTitle,
                    statusKey: HelperWorkflowLocalizationKeys.ppcRestoreStatus,
                    startPercent: 25,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", ppcRestoreSource, "--target", "/Volumes/PPC", "--erase", "--noverify", "--noprompt", "--verbose"],
                    parseToolPercent: false
                )
            )

        case .standard:
            let createinstallmediaPath = (context.sourcePath as NSString).appendingPathComponent("Contents/Resources/createinstallmedia")
            var createArgs: [String] = ["--volume", effectiveTargetPath]
            if request.requiresApplicationPathArg {
                createArgs.append(contentsOf: ["--applicationpath", context.sourcePath])
            }
            createArgs.append("--nointeraction")

            stages.append(
                WorkflowStage(
                    key: "createinstallmedia",
                    titleKey: HelperWorkflowLocalizationKeys.createinstallmediaTitle,
                    statusKey: HelperWorkflowLocalizationKeys.createinstallmediaStatus,
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.isCatalina ? 90 : 98,
                    executable: createinstallmediaPath,
                    arguments: createArgs,
                    parseToolPercent: true
                )
            )

            if request.isCatalina {
                guard let postSource = context.postInstallSourceAppPath else {
                    throw HelperExecutionError.invalidRequest("Brak ścieżki źródłowej do końcowego etapu Cataliny.")
                }
                let targetApp = "/Volumes/Install macOS Catalina/Install macOS Catalina.app"
                stages.append(
                    WorkflowStage(
                        key: "catalina_cleanup",
                        titleKey: HelperWorkflowLocalizationKeys.catalinaCleanupTitle,
                        statusKey: HelperWorkflowLocalizationKeys.catalinaCleanupStatus,
                        startPercent: 90,
                        endPercent: 94,
                        executable: "/bin/rm",
                        arguments: ["-rf", targetApp],
                        parseToolPercent: false
                    )
                )
                stages.append(
                    WorkflowStage(
                        key: "catalina_copy",
                        titleKey: HelperWorkflowLocalizationKeys.catalinaCopyTitle,
                        statusKey: HelperWorkflowLocalizationKeys.catalinaCopyStatus,
                        startPercent: 94,
                        endPercent: 98,
                        executable: "/usr/bin/ditto",
                        arguments: [postSource, targetApp],
                        parseToolPercent: false
                    )
                )
                stages.append(
                    WorkflowStage(
                        key: "catalina_xattr",
                        titleKey: HelperWorkflowLocalizationKeys.catalinaXattrTitle,
                        statusKey: HelperWorkflowLocalizationKeys.catalinaXattrStatus,
                        startPercent: 98,
                        endPercent: 99,
                        executable: "/usr/bin/xattr",
                        arguments: ["-dr", "com.apple.quarantine", targetApp],
                        parseToolPercent: false
                    )
                )
            }

        case .linux:
            stages.append(contentsOf: try buildLinuxWorkflowStages(using: context))
        }

        return stages
    }
}
