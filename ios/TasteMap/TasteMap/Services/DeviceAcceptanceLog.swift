import Foundation

/// Bounded, non-content diagnostics survive device-console cold-launch gaps.
nonisolated enum DeviceAcceptanceLog {
    private static let lock = NSLock()

    static func record(_ event: String) {
        guard event.hasPrefix("TasteMapDiagnostic ") || event.hasPrefix("TasteMapBuildIdentity ") else { return }
        print(event)
        lock.lock()
        defer { lock.unlock() }
        do {
            let bundle = Bundle.main
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let fields = [
                "time": ISO8601DateFormatter().string(from: Date()),
                "build": build,
                "commit": bundle.object(forInfoDictionaryKey: "TasteMapSourceCommit") as? String ?? "unrecorded",
                "source": bundle.object(forInfoDictionaryKey: "TasteMapSourceFingerprint") as? String ?? "unrecorded",
                "pid": String(ProcessInfo.processInfo.processIdentifier),
                "event": event,
            ]
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TasteMapAcceptance", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let file = dir.appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath: file.path) {
                guard FileManager.default.createFile(atPath: file.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { return }
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            // Do not overwrite old evidence or grow without a bound.
            guard try handle.seekToEnd() < 2_000_000 else { return }
            var data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            data.append(0x0a)
            try handle.write(contentsOf: data)
        } catch {
            print("TasteMapDiagnostic category=capture event=persistent_log_unavailable")
        }
    }
}
