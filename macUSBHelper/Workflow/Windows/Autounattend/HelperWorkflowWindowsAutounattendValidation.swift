import Foundation

extension HelperWorkflowExecutor {
    func validateWindowsAutounattendFile(at url: URL, stage: String) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw HelperExecutionError.failed(
                stage: stage,
                exitCode: -1,
                description: "Nie znaleziono pliku odpowiedzi Windows po zapisie."
            )
        }

        do {
            let data = try Data(contentsOf: url)
            try validateWindowsAutounattendXMLData(data, stage: stage)
        } catch let error as HelperExecutionError {
            throw error
        } catch {
            throw HelperExecutionError.failed(
                stage: stage,
                exitCode: -1,
                description: "Nie udało się odczytać pliku odpowiedzi Windows do walidacji: \(error.localizedDescription)"
            )
        }
    }

    func validateWindowsAutounattendXMLData(_ data: Data, stage: String) throws {
        guard !data.isEmpty else {
            throw HelperExecutionError.failed(
                stage: stage,
                exitCode: -1,
                description: "Plik odpowiedzi Windows jest pusty."
            )
        }

        do {
            let document = try XMLDocument(data: data, options: [])
            guard document.rootElement()?.name == "unattend" else {
                throw HelperExecutionError.failed(
                    stage: stage,
                    exitCode: -1,
                    description: "Plik odpowiedzi Windows nie zawiera poprawnego elementu głównego unattend."
                )
            }
        } catch let error as HelperExecutionError {
            throw error
        } catch {
            throw HelperExecutionError.failed(
                stage: stage,
                exitCode: -1,
                description: "Plik odpowiedzi Windows nie jest poprawnym plikiem XML: \(error.localizedDescription)"
            )
        }
    }

    func isWindowsAutounattendLocalAccountNameValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }
}
