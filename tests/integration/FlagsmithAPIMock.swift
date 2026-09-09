import FlyingFox
import Foundation

/// Local HTTP stand-in for the Flagsmith API, recording every request it receives.
final class FlagsmithAPIMock {
    private let server: HTTPServer
    private var running: Task<Void, any Error>?
    let requests = RecordedRequests()

    init() throws {
        server = HTTPServer(address: try .inet(ip4: "127.0.0.1", port: 0))
    }

    deinit {
        running?.cancel()
    }

    /// Starts listening and returns the base URL to configure the Flagsmith client with.
    func start() async throws -> URL {
        running = Task { [server] in try await server.run() }
        try await server.waitUntilListening()
        guard case .ip4(_, port: let port) = await server.listeningAddress,
            let baseURL = URL(string: "http://127.0.0.1:\(port)/api/v1/")
        else {
            throw URLError(.cannotFindHost)
        }
        return baseURL
    }

    func respond(_ route: HTTPRoute, status: HTTPStatusCode = .ok, json: String = "") async {
        await server.appendRoute(route) { [requests] request in
            await requests.record(request)
            return HTTPResponse(
                statusCode: status,
                headers: [.contentType: "application/json"],
                body: Data(json.utf8)
            )
        }
    }
}

actor RecordedRequests {
    private(set) var all: [HTTPRequest] = []

    func record(_ request: HTTPRequest) {
        all.append(request)
    }
}
