import Foundation
import Hummingbird
import HummingbirdElementary
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
    
    router.get("/") { _, _ in
        HTMLResponse {
            MainLayout(title: "Hello there!") {
                WelcomePage()
            }
        }
    }
    
    router.get("/play") { _, _ in
        HTMLResponse {
            MainLayout(title: "Join game") {
                GameJoinPage()
            }
        }
    }
    
    router.get("/create") { _, _ in
        HTMLResponse {
            MainLayout(title: "New game") {
                GameJoinPage(roomCode: connectionManager.generateCode())
            }
        }
    }
    
    router.get("/game") { request, _ in
        HTMLResponse {
            GamePlayLayout(title: "Playing") {
                let results = gameParameters(request: request)
                GamePlayPage(name: results.user, roomCode: results.code)
            }
        }
    }
    
    router.get("/new_game") { request, context in
        return "{\"\(GameParameterConstants.code)\":\"\(connectionManager.generateCode())\"}"
    }
    
    // Separate router for websocket upgrade
    let wsRouter = Router(context: BasicWebSocketRequestContext.self)
    wsRouter.add(middleware: LogRequestsMiddleware(.debug))
    wsRouter.ws("game") { request, _ in
        // only allow upgrade if username query parameter exists
        let params = gameParameters(request: request)
        guard (params.user != nil || params.device != nil) && params.code != nil else {
//            logger.info("Missing code or user or device")
            return .dontUpgrade
        }
        return .upgrade([:])
    } onUpgrade: { inbound, outbound, context in
        // only allow upgrade if username query parameter exists
        var outputStream: ConnectionManager.OutputStream?
        
        let params = gameParameters(request: context.request)
        
        guard let roomCode = params.code else {
            try await outbound.close(.unexpectedServerError, reason: "Invalid room code")
//            logger.info("Missing code")
            return
        }
        
        if let name = params.user {
            outputStream = connectionManager.addUser(name: name, roomCode: roomCode, inbound: inbound, outbound: outbound)
        } else if let device = params.device {
            outputStream = connectionManager.addDevice(name: device, roomCode: roomCode, inbound: inbound, outbound: outbound)
        }
        guard let outputStream else {
            try await outbound.close(.unexpectedServerError, reason: "User connected already")
//            logger.info("This matches an existing user")
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

private func gameParameters(request: Request) -> (device: String?, user: String?, code: String?) {
    var device: String? = nil
    var user: String? = nil
    var code: String? = nil
    if let deviceSegment = request.uri.queryParameters[GameParameterConstants.device.rawValue] {
        device = String(deviceSegment)
    }
    if let usernameSegment = request.uri.queryParameters[GameParameterConstants.username.rawValue] {
        user = String(usernameSegment)
    }
    if let codeSegment = request.uri.queryParameters[GameParameterConstants.code.rawValue] {
        code = String(codeSegment)
    }
    return (device: device, user: user, code: code)
}

enum GameParameterConstants: Substring {
    case device = "device"
    case username = "name"
    case code = "code"
}
