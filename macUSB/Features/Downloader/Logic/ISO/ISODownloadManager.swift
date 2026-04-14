import Foundation
import Combine

// MARK: - Download Phase

enum ISODownloadPhase: Equatable {
    case idle
    case downloading(bytesReceived: Int64, bytesTotal: Int64, bytesPerSecond: Double)
    case done(savedURL: URL)
    case failed(message: String)
    case cancelled
}

// MARK: - ISODownloadManager

@MainActor
final class ISODownloadManager: NSObject, ObservableObject {

    @Published private(set) var phase: ISODownloadPhase = .idle

    var progressFraction: Double {
        guard case .downloading(let received, let total, _) = phase, total > 0 else { return 0 }
        return Double(received) / Double(total)
    }

    var speedText: String {
        guard case .downloading(_, _, let bps) = phase else { return "" }
        return ISODownloadManager.formatSpeed(bps)
    }

    var transferText: String {
        guard case .downloading(let received, let total, _) = phase else { return "" }
        return "\(ISODownloadManager.formatBytes(received)) / \(ISODownloadManager.formatBytes(total))"
    }

    var isActive: Bool {
        if case .idle = phase { return false }
        if case .done = phase { return false }
        if case .failed = phase { return false }
        if case .cancelled = phase { return false }
        return true
    }

    var isFinished: Bool {
        if case .done = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var delegate: ISODownloadDelegate?
    private var speedSamples: [(Date, Int64)] = []
    private var lastSampleBytes: Int64 = 0
    private var speedTimer: Timer?

    // MARK: - Start

    func start(entry: ISOEntry) {
        guard case .directDownload(let url) = entry.kind else { return }
        stop()
        phase = .downloading(bytesReceived: 0, bytesTotal: 0, bytesPerSecond: 0)

        let outputURL = resolveOutputURL(for: entry)

        let delegate = ISODownloadDelegate { [weak self] received, total in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let bps = self.computeSpeed(received: received)
                self.phase = .downloading(bytesReceived: received, bytesTotal: total, bytesPerSecond: bps)
            }
        } completionHandler: { [weak self] tmpURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.speedTimer?.invalidate()
                self.speedTimer = nil
                if let error {
                    if (error as NSError).code == NSURLErrorCancelled {
                        self.phase = .cancelled
                    } else {
                        self.phase = .failed(message: error.localizedDescription)
                    }
                    return
                }
                guard let tmpURL else {
                    self.phase = .failed(message: "Download failed: no file received.")
                    return
                }
                do {
                    let fm = FileManager.default
                    let dir = outputURL.deletingLastPathComponent()
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    if fm.fileExists(atPath: outputURL.path) {
                        try fm.removeItem(at: outputURL)
                    }
                    try fm.moveItem(at: tmpURL, to: outputURL)
                    AppLogging.info("ISO saved to: \(outputURL.path)", category: "ISODownloader")
                    self.phase = .done(savedURL: outputURL)
                } catch {
                    self.phase = .failed(message: "Could not save file: \(error.localizedDescription)")
                }
            }
        }

        self.delegate = delegate
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = urlSession

        let task = urlSession.downloadTask(with: url)
        self.downloadTask = task
        task.resume()

        AppLogging.info("Starting ISO download: \(url.absoluteString)", category: "ISODownloader")
    }

    // MARK: - Stop

    func stop() {
        speedTimer?.invalidate()
        speedTimer = nil
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
        phase = .idle
        speedSamples = []
        lastSampleBytes = 0
    }

    func cancel() {
        speedTimer?.invalidate()
        speedTimer = nil
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
        phase = .cancelled
        speedSamples = []
        lastSampleBytes = 0
    }

    // MARK: - Helpers

    private func resolveOutputURL(for entry: ISOEntry) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let folder = downloads.appendingPathComponent("macUSB")
        let filename = "\(entry.name.replacingOccurrences(of: " ", with: "_"))_\(entry.version.replacingOccurrences(of: " ", with: "_")).iso"
        return folder.appendingPathComponent(filename)
    }

    private func computeSpeed(received: Int64) -> Double {
        let now = Date()
        speedSamples.append((now, received))
        // Keep only last 3 seconds of samples
        speedSamples = speedSamples.filter { now.timeIntervalSince($0.0) <= 3.0 }
        guard speedSamples.count >= 2,
              let first = speedSamples.first,
              let last = speedSamples.last else { return 0 }
        let elapsed = last.0.timeIntervalSince(first.0)
        guard elapsed > 0 else { return 0 }
        let bytesDelta = Double(last.1 - first.1)
        return bytesDelta / elapsed
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1_000_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }

    static func formatSpeed(_ bps: Double) -> String {
        if bps < 1_000_000 {
            return String(format: "%.0f KB/s", bps / 1_000)
        }
        return String(format: "%.1f MB/s", bps / 1_000_000)
    }
}

// MARK: - URLSession Delegate

private final class ISODownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Int64, Int64) -> Void
    let completionHandler: (URL?, Error?) -> Void

    init(progressHandler: @escaping (Int64, Int64) -> Void,
         completionHandler: @escaping (URL?, Error?) -> Void) {
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        completionHandler(location, nil)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            completionHandler(nil, error)
        }
    }
}
