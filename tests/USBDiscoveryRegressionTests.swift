import Foundation
import Darwin

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Data, USBDiscoveryProcessRunner.Failure>?
    func set(_ value: Result<Data, USBDiscoveryProcessRunner.Failure>) {
        lock.lock(); defer { lock.unlock() }
        stored = value
    }
    var value: Result<Data, USBDiscoveryProcessRunner.Failure>? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

@main
private enum USBDiscoveryRegressionTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    static func expectFailure(_ result: Result<Data, USBDiscoveryProcessRunner.Failure>, _ expected: USBDiscoveryProcessRunner.Failure) {
        if case .failure(let actual) = result { expect(actual == expected, "Expected \(expected), received \(actual)") }
        else { fatalError("Expected failure \(expected)") }
    }

    static func expectSuccess(_ result: Result<Data, USBDiscoveryProcessRunner.Failure>, bytes: Int = 2) {
        if case .success(let data) = result { expect(data.count == bytes, "Unexpected output length \(data.count)") }
        else { fatalError("Expected successful fixture: \(result)") }
    }

    static var executable: URL { URL(fileURLWithPath: CommandLine.arguments[0]) }

    static func runner(timeout: TimeInterval = 2, limit: Int = 4 * 1024 * 1024) -> USBDiscoveryProcessRunner {
        USBDiscoveryProcessRunner(executableURL: executable, timeout: timeout, terminationGrace: 0.1, maximumOutputBytes: limit)
    }

    static func main() throws {
        if CommandLine.arguments.count > 1 {
            try fixture(CommandLine.arguments[1])
            return
        }
        ownership()
        scheduling()
        try processes()
        print("PASS: \(checks) USB discovery regression assertions; no diskutil or app launch")
    }

    static func ownership() {
        // Parent results carry a reference; the original iterator reference stays owned by its caller.
        for matchingParent in [2, 3, 4, 0] {
            var refs = [1: 1]
            let result: String? = USBRegistryTraversal.firstValue(
                from: 1,
                retain: { refs[$0, default: 0] += 1; return true },
                release: { entry in
                    expect(refs[entry, default: 0] > 0, "Double release of \(entry)")
                    refs[entry, default: 0] -= 1
                },
                parent: { entry in
                    guard entry < 4 else { return nil }
                    refs[entry + 1, default: 0] += 1
                    return entry + 1
                },
                value: { $0 == matchingParent ? "speed" : nil }
            )
            expect(result == (matchingParent == 0 ? nil : "speed"), "Incorrect ancestor result")
            expect(refs[1] == 1, "Traversal consumed the caller's service reference")
            expect(refs.filter { $0.key != 1 }.values.allSatisfy { $0 == 0 }, "Leaked ancestor")
        }
        var releases = 0
        let missing: Int? = USBRegistryTraversal.firstValue(
            from: 1, retain: { _ in true }, release: { _ in releases += 1 },
            parent: { _ in nil }, value: { _ in nil }
        )
        expect(missing == nil && releases == 1, "Root/failing lookup must release only its retained start")
        let failedRetain: Int? = USBRegistryTraversal.firstValue(
            from: 1, retain: { _ in false }, release: { _ in fatalError("Release after failed retain") },
            parent: { _ in fatalError("Lookup after failed retain") }, value: { _ in nil }
        )
        expect(failedRetain == nil, "Failed retain must stop traversal")
    }

    static func scheduling() {
        var policy = USBDriveRefreshPolicy()
        expect(policy.begin(at: 0, visible: true, active: true), "Initial scan must start immediately")
        expect(!policy.begin(at: 100, visible: true, active: true, force: true), "Forced request overlapped a scan")
        policy.finish()
        for tick in [0.5, 1.0, 1.5, 2.0] {
            expect(!policy.begin(at: tick, visible: true, active: true), "Tick bypassed throttling")
        }
        expect(policy.begin(at: 2.5, visible: true, active: true), "Refresh did not resume after interval")
        policy.finish()
        expect(!policy.begin(at: 10, visible: false, active: true, force: true), "Hidden view polled")
        expect(!policy.begin(at: 10, visible: true, active: false, force: true), "Inactive app polled")
        expect(policy.begin(at: 2.6, visible: true, active: true, force: true), "Activation must refresh immediately")
        policy.finish()
        expect(!policy.isRunning, "Completion left discovery busy")
    }

    static func processes() throws {
        let query = runner()
        expectSuccess(query.run(arguments: ["good"]))
        expectSuccess(query.run(arguments: ["large"]), bytes: 10 * 32 * 1024)
        expectFailure(query.run(arguments: ["nonzero"]), .exitStatus(3))
        expectFailure(runner(limit: 1024).run(arguments: ["large"]), .outputLimit)
        let invalid = USBDiscoveryProcessRunner(executableURL: URL(fileURLWithPath: "/nonexistent/macusb-test-fixture"))
        expectFailure(invalid.run(arguments: []), .launchFailed)
        expectFailure(invalid.run(arguments: []), .launchFailed)
        let cancelled = USBDiscoveryCancellation()
        cancelled.cancel()
        expectFailure(query.run(arguments: ["good"], cancellation: cancelled), .cancelled)
        expectSuccess(query.run(arguments: ["good"]))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macusb-fixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for mode in ["hang", "ignoreTerm"] {
            let marker = directory.appendingPathComponent(mode)
            let bounded = runner(timeout: 0.3)
            let start = ProcessInfo.processInfo.systemUptime
            expectFailure(bounded.run(arguments: [mode, marker.path]), .timedOut)
            expect(ProcessInfo.processInfo.systemUptime - start < 1.5, "Hung child exceeded bounded return")
            try expectReaped(marker)
            expectSuccess(bounded.run(arguments: ["good"]))
        }

        let marker = directory.appendingPathComponent("cancel")
        let token = USBDiscoveryCancellation()
        let box = ResultBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            box.set(query.run(arguments: ["ignoreTerm", marker.path], cancellation: token))
            group.leave()
        }
        try waitForMarker(marker)
        expectFailure(query.run(arguments: ["good"]), .busy)
        token.cancel()
        expect(group.wait(timeout: .now() + 2) == .success, "Cancellation did not return")
        expectFailure(box.value!, .cancelled)
        try expectReaped(marker)
        expectSuccess(query.run(arguments: ["good"]))

        // Race cancellation with launch/normal exit; either terminal outcome is valid.
        for _ in 0..<3 {
            let race = USBDiscoveryCancellation()
            let raced = ResultBox()
            let done = DispatchGroup()
            done.enter()
            DispatchQueue.global().async {
                raced.set(query.run(arguments: ["good"], cancellation: race)); done.leave()
            }
            race.cancel()
            expect(done.wait(timeout: .now() + 2) == .success, "Launch/cancel race hung")
            if case .failure(let reason) = raced.value! { expect(reason == .cancelled, "Unexpected race failure") }
            else { expectSuccess(raced.value!) }
            expectSuccess(query.run(arguments: ["good"]))
        }

        // Warm-up has completed; repeated ordinary queries must not leak pipe descriptors.
        let initialFDs = openDescriptorCount()
        for _ in 0..<5 { expectSuccess(query.run(arguments: ["good"])) }
        expect(openDescriptorCount() <= initialFDs, "Process/pipe descriptor leak")

        let closing = runner()
        let shutdownMarker = directory.appendingPathComponent("shutdown")
        let shutdownBox = ResultBox()
        let shutdownGroup = DispatchGroup()
        shutdownGroup.enter()
        DispatchQueue.global().async {
            shutdownBox.set(closing.run(arguments: ["ignoreTerm", shutdownMarker.path])); shutdownGroup.leave()
        }
        try waitForMarker(shutdownMarker)
        closing.shutdown()
        expect(shutdownGroup.wait(timeout: .now() + 2) == .success, "Shutdown did not finish owned query")
        expectFailure(shutdownBox.value!, .cancelled)
        try expectReaped(shutdownMarker)
        expectFailure(closing.run(arguments: ["good"]), .cancelled)
    }

    static func waitForMarker(_ marker: URL) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !FileManager.default.fileExists(atPath: marker.path), ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        expect(FileManager.default.fileExists(atPath: marker.path), "Fixture never started")
    }

    static func expectReaped(_ marker: URL) throws {
        let pid = pid_t(try String(contentsOf: marker, encoding: .utf8))!
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while kill(pid, 0) == 0, ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        expect(kill(pid, 0) == -1 && errno == ESRCH, "Fixture child remains alive or unreaped")
    }

    static func openDescriptorCount() -> Int {
        (0..<1024).filter { fcntl(Int32($0), F_GETFD) != -1 }.count
    }

    static func fixture(_ mode: String) throws {
        switch mode {
        case "good":
            try FileHandle.standardOutput.write(contentsOf: Data("ok".utf8))
        case "large":
            let chunk = Data(repeating: 65, count: 32 * 1024)
            for _ in 0..<10 {
                try FileHandle.standardOutput.write(contentsOf: chunk)
                try FileHandle.standardError.write(contentsOf: chunk)
            }
        case "nonzero":
            exit(3)
        case "hang", "ignoreTerm":
            if mode == "ignoreTerm" { signal(SIGTERM, SIG_IGN) }
            try String(getpid()).write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
            while true { pause() }
        default:
            fatalError("Unknown synthetic fixture")
        }
    }
}
