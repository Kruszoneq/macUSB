import Foundation

final class MacOSLocalInstallerLegacyParser: NSObject, @unchecked Sendable {
    private final class DistributionDelegate:
        NSObject,
        XMLParserDelegate,
        @unchecked Sendable
    {
        private static let supportedKeys: Set<String> = [
            "macOSProductVersion",
            "macOSProductBuildVersion",
            "ProductVersion",
            "ProductBuildVersion",
            "OSVersion",
            "Build"
        ]

        private(set) var values: [String: String] = [:]
        private var currentElement: String?
        private var currentText = ""
        private var pendingKey: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if pendingKey != nil && elementName != "string" {
                pendingKey = nil
            }
            currentElement = elementName
            currentText = ""

            if elementName == "options",
               let build = attributeDict["osBuildVersion"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !build.isEmpty {
                values["osBuildVersion"] = build
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentElement == "key" || currentElement == "string" else {
                return
            }
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "key" {
                pendingKey = Self.supportedKeys.contains(value) ? value : nil
            } else if elementName == "string", let pendingKey {
                if !value.isEmpty {
                    values[pendingKey] = value
                }
                self.pendingKey = nil
            }
            currentElement = nil
            currentText = ""
        }
    }

    private let processRunner: MacOSLocalInstallerProcessRunner

    init(processRunner: MacOSLocalInstallerProcessRunner) {
        self.processRunner = processRunner
    }

    func readIdentity(
        packageURL: URL,
        fallbackVersion: String?,
        temporaryRoot: URL
    ) async throws -> MacOSLocalInstallerIdentity? {
        let extractionURL = temporaryRoot.appendingPathComponent(
            "legacy-distribution-\(UUID().uuidString)",
            isDirectory: true
        )
        try await macOSLocalInstallerOffMain {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: extractionURL,
                withIntermediateDirectories: true
            )
        }

        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/xar"),
            arguments: [
                "-xf",
                packageURL.path,
                "-C",
                extractionURL.path,
                "Distribution"
            ]
        )
        guard result.terminationStatus == 0 else {
            throw MacOSLocalInstallerProcessFailure(
                operation: "xar Distribution",
                result: result
            )
        }

        let distributionURL = extractionURL.appendingPathComponent("Distribution")
        return try await macOSLocalInstallerOffMain {
            try Task.checkCancellation()
            return Self.parseDistribution(
                at: distributionURL,
                fallbackVersion: fallbackVersion
            )
        }
    }

    private static func parseDistribution(
        at distributionURL: URL,
        fallbackVersion: String?
    ) -> MacOSLocalInstallerIdentity? {
        guard let distributionData = try? Data(contentsOf: distributionURL) else {
            return nil
        }

        let delegate = DistributionDelegate()
        let parser = XMLParser(data: distributionData)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }

        let version = firstNonEmptyValue(
            for: ["macOSProductVersion", "ProductVersion", "OSVersion"],
            in: delegate.values
        ) ?? fallbackVersion
        let build = firstNonEmptyValue(
            for: [
                "macOSProductBuildVersion",
                "ProductBuildVersion",
                "osBuildVersion",
                "Build"
            ],
            in: delegate.values
        )
        return MacOSLocalInstallerIdentity(version: version, build: build)
    }

    private static func firstNonEmptyValue(
        for keys: [String],
        in values: [String: String]
    ) -> String? {
        for key in keys {
            guard
                let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                continue
            }
            return value
        }
        return nil
    }
}
