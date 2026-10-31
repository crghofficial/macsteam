// Client package fetcher
import Foundation
import CryptoKit

enum PackageFetcher {

    static let cdnBase = "https://client-update.fastly.steamstatic.com"

    private struct Component {
        let name: String
        let sha2: String
    }

    static func stageFromValve(progress: (@Sendable (String) -> Void)? = nil) throws {
        let fm = FileManager.default
        let manifestURL = localManifest()
        guard let manifestURL,
              let text = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw StepFailure(step: L10n.text("Read manifest"),
                          detail: L10n.text("No steam_client_osx manifest in the package dir. Open Steam once so it unbundles, then try again."))
        }

        let components = parse(text)
        guard !components.isEmpty else {
            throw StepFailure(step: L10n.text("Parse manifest"),
                          detail: L10n.text("The client manifest listed no component files."))
        }

        try Paths.ensureDir(Paths.packageDir)

        let needed = components.filter { !fileValid($0, in: Paths.packageDir, fm: fm) }
        if needed.isEmpty {
            progress?(L10n.text("Client files already staged"))
            return
        }

        progress?(L10n.format("Downloading %1$@ client files from Valve", needed.count))
        try download(needed, into: Paths.packageDir, progress: progress)
    }

    // MARK: - Manifest

    private static func localManifest() -> URL? {
        let fm = FileManager.default
        let names = [
            "steam_client_osx.manifest",
            "steam_client_signed-2_osx.manifest",
            "steam_client_signed_osx.manifest",
        ]
        for name in names {
            let url = Paths.packageDir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func parse(_ text: String) -> [Component] {
        var out: [Component] = []
        var depth = 0
        var blockName = ""             // header seen just before the current "{"
        var nameStack: [String] = []   // block name per open brace

        var file: String?, sha2: String?, zipvz: String?, sha2vz: String?
        func reset() { file = nil; sha2 = nil; zipvz = nil; sha2vz = nil }

        func flush(_ name: String) {
            defer { reset() }
            if name == "steamchina" { return }
            if let zipvz, let sha2vz {
                out.append(Component(name: zipvz, sha2: sha2vz))
            } else if let file, let sha2 {
                out.append(Component(name: file, sha2: sha2))
            }
        }

        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "{" {
                depth += 1
                nameStack.append(blockName)
                reset()
                continue
            }
            if line == "}" {
                let name = nameStack.popLast() ?? ""
                flush(name)
                depth -= 1
                continue
            }
            if let (key, value) = keyValue(line) {
                switch key {
                case "file": file = value
                case "sha2": sha2 = value
                case "zipvz": zipvz = value
                case "sha2vz": sha2vz = value
                default: break
                }
            } else if let solo = soloToken(line) {
                blockName = solo
            }
        }
        return out
    }

    private static func soloToken(_ line: String) -> String? {
        let parts = line.components(separatedBy: "\"").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return parts.count == 1 ? parts[0] : nil
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        let parts = line.components(separatedBy: "\"").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: - Verify

    private static func fileValid(_ c: Component, in dir: URL, fm: FileManager) -> Bool {
        let url = dir.appendingPathComponent(c.name)
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }
        return sha256Hex(data) == c.sha2.lowercased()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Download

    private static func download(_ components: [Component],
                                 into dir: URL,
                                 progress: (@Sendable (String) -> Void)?) throws {
        let session = URLSession(configuration: .ephemeral)
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: 8)   // cap concurrent transfers
        let box = ResultBox()
        let doneCount = Counter()
        let total = components.count

        for c in components {
            gate.wait()
            group.enter()
            guard let url = URL(string: "\(cdnBase)/\(c.name)") else {
                box.record(StepFailure(step: L10n.text("Build URL"), detail: c.name))
                gate.signal()
                group.leave()
                continue
            }
            let task = session.downloadTask(with: url) { tmp, response, error in
                defer { gate.signal(); group.leave() }
                if box.hasError { return }   // another file already failed
                if let error {
                    box.record(StepFailure(step: L10n.format("Download %1$@", c.name), detail: error.localizedDescription))
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    box.record(StepFailure(step: L10n.format("Download %1$@", c.name), detail: "HTTP \(code)"))
                    return
                }
                guard let tmp, let data = try? Data(contentsOf: tmp) else {
                    box.record(StepFailure(step: L10n.format("Download %1$@", c.name), detail: L10n.text("empty response body")))
                    return
                }
                guard sha256Hex(data) == c.sha2.lowercased() else {
                    box.record(StepFailure(step: L10n.format("Verify %1$@", c.name), detail: L10n.text("sha2 mismatch")))
                    return
                }
                let dest = dir.appendingPathComponent(c.name)
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try data.write(to: dest, options: .atomic)
                } catch {
                    box.record(StepFailure(step: L10n.format("Write %1$@", c.name), detail: error.localizedDescription))
                    return
                }
                let n = doneCount.increment()
                progress?(L10n.format("Downloaded %1$@/%2$@ client files", n, total))
            }
            task.resume()
        }

        group.wait()
        if let e = box.firstError { throw e }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var error: Error?
        var hasError: Bool { lock.lock(); defer { lock.unlock() }; return error != nil }
        var firstError: Error? { lock.lock(); defer { lock.unlock() }; return error }
        func record(_ e: Error) {
            lock.lock(); defer { lock.unlock() }
            if error == nil { error = e }
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }
}
