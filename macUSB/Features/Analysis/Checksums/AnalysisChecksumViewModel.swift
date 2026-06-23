import Foundation
import AppKit
import Combine

@MainActor
final class AnalysisChecksumViewModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case running
        case completed
        case cancelled
        case failed
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var progress: Double = 0
    @Published private(set) var checksum: String?
    @Published private(set) var failureMessage: String?

    let fileURL: URL
    private var checksumTask: Task<Void, Never>?
    private let service = AnalysisChecksumService()

    var isRunning: Bool {
        phase == .running
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        checksumTask?.cancel()
    }

    func start() {
        guard phase != .running else { return }

        checksumTask?.cancel()
        checksum = nil
        failureMessage = nil
        progress = 0
        phase = .running

        let sourceURL = fileURL
        let service = service
        checksumTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let digest = try await service.calculateSHA256(for: sourceURL) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.phase == .running else { return }
                        self?.progress = progress.fraction
                    }
                }

                try Task.checkCancellation()

                await MainActor.run { [weak self] in
                    guard self?.phase == .running else { return }
                    self?.progress = 1
                    self?.checksum = digest
                    self?.phase = .completed
                    self?.checksumTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    AppLogging.info(
                        "Anulowano obliczanie SHA-256 dla ISO: \(sourceURL.path)",
                        category: "Checksum"
                    )
                }
                await MainActor.run { [weak self] in
                    self?.markCancelled()
                }
            } catch {
                await MainActor.run {
                    AppLogging.error(
                        "Błąd obliczania SHA-256 dla ISO \(sourceURL.path): \(error.localizedDescription)",
                        category: "Checksum"
                    )
                }
                await MainActor.run { [weak self] in
                    self?.failureMessage = String(localized: "checksum.sheet.failed.description")
                    self?.phase = .failed
                    self?.checksumTask = nil
                }
            }
        }
    }

    func cancelFromUser() {
        guard phase == .running else { return }
        checksumTask?.cancel()
        markCancelled()
    }

    func cancelIfRunningForSheetClose() {
        guard phase == .running else { return }
        checksumTask?.cancel()
    }

    func copyChecksumToPasteboard() {
        guard let checksum else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(checksum, forType: .string)
        AppLogging.info("Skopiowano SHA-256 ISO do schowka.", category: "Checksum")
    }

    private func markCancelled() {
        checksumTask = nil
        checksum = nil
        failureMessage = nil
        progress = 0
        phase = .cancelled
    }
}
