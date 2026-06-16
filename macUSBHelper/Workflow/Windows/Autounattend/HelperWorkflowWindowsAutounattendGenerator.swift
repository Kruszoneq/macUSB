import Foundation

extension HelperWorkflowExecutor {
    func runWindowsCreateAutounattendStage(_ stage: WorkflowStage) throws {
        guard let configuration = request.windowsAutounattendConfiguration,
              configuration.shouldGenerateFile else {
            return
        }

        let targetVolumePath = windowsPreparedTargetVolumePath ?? "/Volumes/\(request.targetLabel)"
        let targetURL = URL(fileURLWithPath: targetVolumePath)
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie znaleziono zamontowanego woluminu docelowego przed utworzeniem Autounattend.xml."
            )
        }

        let xmlData = try buildWindowsAutounattendXMLData(
            configuration: configuration,
            stage: stage
        )
        try validateWindowsAutounattendXMLData(xmlData, stage: stage.key)

        let outputURL = windowsAutounattendOutputURL(
            in: targetURL,
            configuration: configuration
        )
        try prepareWindowsAutounattendOutputDirectory(for: outputURL, stage: stage.key)

        do {
            try xmlData.write(to: outputURL, options: .atomic)
        } catch {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się zapisać pliku odpowiedzi Windows: \(error.localizedDescription)"
            )
        }

        try validateWindowsAutounattendFile(at: outputURL, stage: stage.key)

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows answer file generated at \(outputURL.path)",
            shouldAdvancePercent: false
        )
    }

    func windowsAutounattendOutputURL(
        in targetURL: URL,
        configuration: WindowsAutounattendConfigurationPayload
    ) -> URL {
        if configuration.requiresWindowsPE {
            return targetURL.appendingPathComponent("Autounattend.xml")
        }

        return targetURL
            .appendingPathComponent("sources")
            .appendingPathComponent("$OEM$")
            .appendingPathComponent("$$")
            .appendingPathComponent("Panther")
            .appendingPathComponent("unattend.xml")
    }

    private func prepareWindowsAutounattendOutputDirectory(for outputURL: URL, stage: String) throws {
        let directoryURL = outputURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw HelperExecutionError.failed(
                stage: stage,
                exitCode: -1,
                description: "Nie udało się utworzyć katalogu dla pliku odpowiedzi Windows: \(error.localizedDescription)"
            )
        }
    }

    private func buildWindowsAutounattendXMLData(
        configuration: WindowsAutounattendConfigurationPayload,
        stage: WorkflowStage
    ) throws -> Data {
        if configuration.createLocalAccount {
            guard let accountName = configuration.normalizedLocalAccountName,
                  isWindowsAutounattendLocalAccountNameValid(accountName) else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Nazwa konta lokalnego dla Autounattend.xml jest nieprawidłowa."
                )
            }
        }
        let root = XMLElement(name: "unattend")
        root.addNamespace(XMLNode.namespace(withName: "", stringValue: "urn:schemas-microsoft-com:unattend") as! XMLNode)
        root.addNamespace(XMLNode.namespace(withName: "wcm", stringValue: "http://schemas.microsoft.com/WMIConfig/2002/State") as! XMLNode)

        if configuration.skipHardwareRequirements {
            root.addChild(windowsPESettingsElement(configuration: configuration))
        }

        if configuration.preventDeviceEncryption {
            root.addChild(specializeSettingsElement(configuration: configuration))
        }

        if configuration.disableDataCollection
            || configuration.skipWirelessSetup
            || configuration.skipMicrosoftAccountRequirement
            || configuration.createLocalAccount {
            root.addChild(oobeSystemSettingsElement(configuration: configuration))
        }

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "utf-8"
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private func windowsPESettingsElement(configuration: WindowsAutounattendConfigurationPayload) -> XMLElement {
        let settings = XMLElement(name: "settings")
        settings.addAttribute(XMLNode.attribute(withName: "pass", stringValue: "windowsPE") as! XMLNode)

        if configuration.skipHardwareRequirements {
            settings.addChild(windowsPESetupComponentElement())
        }
        return settings
    }

    private func windowsPESetupComponentElement() -> XMLElement {
        let component = componentElement(named: "Microsoft-Windows-Setup")
        let runSynchronous = XMLElement(name: "RunSynchronous")
        let commands = [
            "cmd /c reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f",
            "cmd /c reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f",
            "cmd /c reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f"
        ]

        for (index, command) in commands.enumerated() {
            let commandElement = XMLElement(name: "RunSynchronousCommand")
            commandElement.addAttribute(XMLNode.attribute(withName: "wcm:action", stringValue: "add") as! XMLNode)
            commandElement.addChild(textElement(name: "Order", value: "\(index + 1)"))
            commandElement.addChild(textElement(name: "Path", value: command))
            runSynchronous.addChild(commandElement)
        }

        component.addChild(runSynchronous)
        return component
    }

    private func specializeSettingsElement(configuration: WindowsAutounattendConfigurationPayload) -> XMLElement {
        let settings = XMLElement(name: "settings")
        settings.addAttribute(XMLNode.attribute(withName: "pass", stringValue: "specialize") as! XMLNode)

        if configuration.preventDeviceEncryption {
            settings.addChild(deploymentComponentElement())
        }
        return settings
    }

    private func deploymentComponentElement() -> XMLElement {
        let component = componentElement(named: "Microsoft-Windows-Deployment")
        let runSynchronous = XMLElement(name: "RunSynchronous")
        let commandElement = XMLElement(name: "RunSynchronousCommand")
        commandElement.addAttribute(XMLNode.attribute(withName: "wcm:action", stringValue: "add") as! XMLNode)
        commandElement.addChild(textElement(name: "Order", value: "1"))
        commandElement.addChild(textElement(
            name: "Path",
            value: "cmd /c reg add HKLM\\SYSTEM\\CurrentControlSet\\Control\\BitLocker /v PreventDeviceEncryption /t REG_DWORD /d 1 /f"
        ))

        runSynchronous.addChild(commandElement)
        component.addChild(runSynchronous)
        return component
    }

    private func oobeSystemSettingsElement(configuration: WindowsAutounattendConfigurationPayload) -> XMLElement {
        let settings = XMLElement(name: "settings")
        settings.addAttribute(XMLNode.attribute(withName: "pass", stringValue: "oobeSystem") as! XMLNode)

        let component = componentElement(named: "Microsoft-Windows-Shell-Setup")
        let oobe = XMLElement(name: "OOBE")

        if configuration.skipMicrosoftAccountRequirement || configuration.createLocalAccount {
            oobe.addChild(textElement(name: "HideOnlineAccountScreens", value: "true"))
        }
        if configuration.skipWirelessSetup {
            oobe.addChild(textElement(name: "HideWirelessSetupInOOBE", value: "true"))
        }
        if configuration.disableDataCollection {
            oobe.addChild(textElement(name: "ProtectYourPC", value: "3"))
        }
        if oobe.childCount > 0 {
            component.addChild(oobe)
        }

        if configuration.createLocalAccount,
           let accountName = configuration.normalizedLocalAccountName {
            let userAccounts = XMLElement(name: "UserAccounts")
            let localAccounts = XMLElement(name: "LocalAccounts")
            let localAccount = XMLElement(name: "LocalAccount")
            localAccount.addAttribute(XMLNode.attribute(withName: "wcm:action", stringValue: "add") as! XMLNode)
            localAccount.addChild(textElement(name: "Name", value: accountName))
            localAccount.addChild(textElement(name: "DisplayName", value: accountName))
            localAccount.addChild(textElement(name: "Group", value: "Administrators"))
            localAccounts.addChild(localAccount)
            userAccounts.addChild(localAccounts)
            component.addChild(userAccounts)
        }

        settings.addChild(component)
        return settings
    }

    private func componentElement(named name: String) -> XMLElement {
        let component = XMLElement(name: "component")
        component.addAttribute(XMLNode.attribute(withName: "name", stringValue: name) as! XMLNode)
        component.addAttribute(XMLNode.attribute(withName: "processorArchitecture", stringValue: windowsAutounattendProcessorArchitecture) as! XMLNode)
        component.addAttribute(XMLNode.attribute(withName: "publicKeyToken", stringValue: "31bf3856ad364e35") as! XMLNode)
        component.addAttribute(XMLNode.attribute(withName: "language", stringValue: "neutral") as! XMLNode)
        component.addAttribute(XMLNode.attribute(withName: "versionScope", stringValue: "nonSxS") as! XMLNode)
        return component
    }

    private func textElement(name: String, value: String) -> XMLElement {
        let element = XMLElement(name: name)
        element.stringValue = value
        return element
    }
}
