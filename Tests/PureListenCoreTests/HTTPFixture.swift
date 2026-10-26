import Foundation
import Network

/// 仅监听本机临时端口；测试不依赖网易/B站账号、外网或用户代理。
final class HTTPFixture: @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = ["Content-Type": "application/octet-stream"]
        var body = Data(repeating: 42, count: 8192)
        var delay: Double = 0
        var chunkSize: Int? = nil
        var chunkInterval: Double = 0
        var declaredLength: Int? = nil
    }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "PureListen.tests.http")
    private var connections: [NWConnection] = []
    let baseURL: String

    convenience init(handler: @escaping (String) -> Reply) throws {
        try self.init(requestHandler: { path, _ in handler(path) })
    }

    init(requestHandler handler: @escaping (String, [String: String]) -> Reply) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue.global())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, let port = listener.port else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
        baseURL = "http://127.0.0.1:\(port.rawValue)"
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, data: Data(), handler: handler)
        }
    }

    private func receive(_ connection: NWConnection, data: Data, handler: @escaping (String, [String: String]) -> Reply) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, done, error in
            guard let self else { connection.cancel(); return }
            var request = data
            if let chunk { request.append(chunk) }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if done || error != nil { connection.cancel() }
                else { self.receive(connection, data: request, handler: handler) }
                return
            }
            let path = text.components(separatedBy: " ").dropFirst().first ?? "/"
            var requestHeaders: [String: String] = [:]
            for line in text.components(separatedBy: "\r\n").dropFirst() {
                let pair = line.split(separator: ":", maxSplits: 1)
                if pair.count == 2 { requestHeaders[String(pair[0]).lowercased()] = pair[1].trimmingCharacters(in: .whitespaces) }
            }
            let reply = handler(path, requestHeaders)
            self.queue.asyncAfter(deadline: .now() + reply.delay) {
                var headers = reply.headers
                headers["Content-Length"] = String(reply.declaredLength ?? reply.body.count)
                headers["Connection"] = "close"
                let header = "HTTP/1.1 \(reply.status) Test\r\n" + headers.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
                if let chunkSize = reply.chunkSize {
                    connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
                        self.sendChunks(connection, body: reply.body, offset: 0, count: chunkSize, interval: reply.chunkInterval)
                    })
                } else {
                    connection.send(content: Data(header.utf8) + reply.body, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
    }

    private func sendChunks(_ connection: NWConnection, body: Data, offset: Int, count: Int, interval: Double) {
        guard offset < body.count else { connection.cancel(); return }
        let end = min(body.count, offset + max(1, count))
        connection.send(content: body[offset..<end], completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }
            self.queue.asyncAfter(deadline: .now() + interval) {
                self.sendChunks(connection, body: body, offset: end, count: count, interval: interval)
            }
        })
    }

    func stop() {
        listener.cancel()
        queue.sync { connections.forEach { $0.cancel() }; connections = [] }
    }
}
