// Local package server for client downgrade
import Foundation
import Network

final class PackageServer {

    private let root: URL
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.macsteam.packageserver")
    private var listener: NWListener?

    init(root: URL, port: UInt16 = 1666) {
        self.root = root
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        params.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            throw StepFailure(step: L10n.text("Start package server"), detail: error.localizedDescription)
        }
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        let box = StartResult()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let err):
                box.error = err.localizedDescription
                ready.signal()
            default:
                break
            }
        }
        let serveRoot = root
        listener.newConnectionHandler = { conn in
            let q = DispatchQueue(label: "com.macsteam.packageserver.conn")
            conn.start(queue: q)
            PackageServer.readRequest(conn, root: serveRoot, buffer: Data())
        }
        listener.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            stop()
            throw StepFailure(step: L10n.text("Start package server"),
                              detail: L10n.format("timed out waiting for port %1$@", port.rawValue))
        }
        if let e = box.error {
            stop()
            throw StepFailure(step: L10n.text("Start package server"), detail: e)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private final class StartResult: @unchecked Sendable {
        var error: String?
    }

    // MARK: - Connection handling

    private static func readRequest(_ conn: NWConnection, root: URL, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, isComplete, error in
            var buffer = buffer
            if let chunk, !chunk.isEmpty {
                buffer.append(chunk)
            }

            let terminator = Data("\r\n\r\n".utf8)
            if let headerEnd = buffer.range(of: terminator) {
                let head = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
                handle(requestHead: head, root: root, on: conn)
                return
            }

            if error != nil || isComplete {
                handle(requestHead: buffer, root: root, on: conn)
                return
            }
            if buffer.count > 64 * 1024 {
                respondError(conn, status: "400 Bad Request")
                return
            }
            readRequest(conn, root: root, buffer: buffer)
        }
    }

    private static func handle(requestHead head: Data, root: URL, on conn: NWConnection) {
        guard let text = String(data: head, encoding: .utf8),
              let requestLine = text.split(separator: "\r\n", maxSplits: 1,
                                           omittingEmptySubsequences: false).first
        else {
            respondError(conn, status: "400 Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            respondError(conn, status: "405 Method Not Allowed")
            return
        }

        guard let fileURL = resolve(rawTarget: String(parts[1]), root: root) else {
            respondError(conn, status: "404 Not Found")
            return
        }
        serveFile(fileURL, on: conn)
    }

    private static func resolve(rawTarget: String, root: URL) -> URL? {
        var target = rawTarget
        if let q = target.firstIndex(of: "?") {
            target = String(target[..<q])
        }
        guard target.hasPrefix("/") else { return nil }
        let name = String(target.dropFirst()).removingPercentEncoding ?? String(target.dropFirst())

        guard !name.isEmpty, !name.contains("/"), name != "..", name != "." else { return nil }

        let candidate = root.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
              !isDir.boolValue
        else { return nil }
        return candidate
    }

    private static func serveFile(_ url: URL, on conn: NWConnection) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            respondError(conn, status: "404 Not Found")
            return
        }
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/octet-stream\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Connection: close\r\n\r\n"

        var out = Data(header.utf8)
        out.append(data)
        send(out, on: conn)
    }

    private static func respondError(_ conn: NWConnection, status: String) {
        let body = Data(status.utf8)
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: text/plain\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        send(out, on: conn)
    }

    private static func send(_ data: Data, on conn: NWConnection) {
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
