import Foundation
import Hummingbird
import HummingbirdWebSocket
import HummingbirdWSCompression
import Logging
import ServiceLifecycle

protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
}

func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    var logger = Logger(label: "mathgame-server")
    logger.logLevel = .trace
    let connectionManager = ConnectionManager(logger: logger)

    // Router
    let router = Router()
    router.add(middleware: LogRequestsMiddleware(.debug))
    router.add(middleware: FileMiddleware(logger: logger))
    
    router.get("/new_game") { request, context in
        return "{\"code\":\"\(connectionManager.generateCode())\"}"
    }
    
    // Separate router for websocket upgrade
    let wsRouter = Router(context: BasicWebSocketRequestContext.self)
    wsRouter.add(middleware: LogRequestsMiddleware(.debug))
    wsRouter.ws("game") { request, _ in
        // only allow upgrade if username query parameter exists
        guard (request.uri.queryParameters["username"] != nil || request.uri.queryParameters["device"] != nil) && request.uri.queryParameters["code"] != nil else {
            return .dontUpgrade
        }
        return .upgrade([:])
    } onUpgrade: { inbound, outbound, context in
        // only allow upgrade if username query parameter exists
        var outputStream: ConnectionManager.OutputStream?
        
        guard let roomCode = context.request.uri.queryParameters["code"] else {
            try await outbound.close(.unexpectedServerError, reason: "Invalid room code")
            return
        }
        
        if let name = context.request.uri.queryParameters["username"] {
            outputStream = connectionManager.addUser(name: String(name), roomCode: String(roomCode), inbound: inbound, outbound: outbound)
        } else if let device = context.request.uri.queryParameters["device"] {
            outputStream = connectionManager.addDevice(name: String(device), roomCode: String(roomCode), inbound: inbound, outbound: outbound)
        }
        guard let outputStream else {
            try await outbound.close(.unexpectedServerError, reason: "User connected already")
            return
        }
        
        for try await output in outputStream {
            switch output {
            case .frame(let frame):
                try await outbound.write(frame)
            case .close(let reason):
                try await outbound.close(.unexpectedServerError, reason: reason)
            }
        }
    }

    var app = Application(
        router: router,
        server: .http1WebSocketUpgrade(webSocketRouter: wsRouter, configuration: .init(extensions: [.perMessageDeflate()])),
        configuration: .init(address: .hostname(arguments.hostname, port: arguments.port)),
        logger: logger
    )
    app.addServices(connectionManager)
    
    
    
    return app
}
