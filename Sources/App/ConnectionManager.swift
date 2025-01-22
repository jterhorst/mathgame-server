
import AsyncAlgorithms
import Hummingbird
import HummingbirdWebSocket
import Logging
import NIOConcurrencyHelpers
import ServiceLifecycle
import Foundation

struct ConnectionManager: Service {
    enum Output {
        case close(String?)
        case frame(WebSocketOutboundWriter.OutboundFrame)
    }

    typealias OutputStream = AsyncChannel<Output>
    struct Connection {
        let playerName: String?
        let deviceName: String?
        let roomCode: String
        let inbound: WebSocketInboundStream
        let outbound: OutputStream
    }

    actor OutboundConnections {
        init(logger: Logger) {
            self.logger = logger
            self.gameConnections = [:]
        }

        func send(game: String, event: Event) async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(event), let json = String(data: data, encoding: .utf8) else { return }
            guard let connections = self.gameConnections[game] else {
                return
            }
            for connection in connections.values {
                self.logger.info("Send", metadata: ["user": .string(connection.playerName ?? connection.deviceName ?? "unknown"), "message": .string(json)])
                await connection.outbound.send(.frame(.text(json)))
            }
        }

        func add(game: String, name: String, outbound: Connection) async -> Bool {
            if self.gameConnections[game] == nil {
                logger.info("Game failed with code \(game)")
                self.gameConnections[game] = [:]
            }
            guard self.gameConnections[game]?[name] == nil else {
                logger.info("Name \(name) already exists on this game \(game).")
                return false
            }
            self.gameConnections[game]?[name] = outbound
            if self.scores[game] == nil {
                self.scores[game] = [:]
            }
            self.scores[game]?[name] = 0
            logger.info("Added \(name) to game \(game). Players now include: \(String(describing: self.gameConnections[game]))")
            // await self.send("\(name) joined")
            await self.updateBattle(connection: outbound)
            await self.send(game: game, event: Event(type: .join, data: name, playerName: name, players: getPlayers(game: game), activeBattle: self.currentBattle[game]))
            return true
        }

        func remove(game: String, name: String) async {
            self.gameConnections[game]?[name] = nil
            self.scores[game]?[name] = nil
            // await self.send("\(name) left")
            await self.send(game: game, event: Event(type: .leave, data: name, playerName: name, players: getPlayers(game: game), activeBattle: self.currentBattle[game]))
        }

        func updateScore(game: String, name: String) async {
            var updatedScores = scores[game] ?? [:]
            updatedScores[name] = (updatedScores[name] ?? 0) + 1
            await self.send(game: game, event: Event(type: .answer, data: name, playerName: name, players: getPlayers(game: game), activeBattle: self.currentBattle[game]))
            self.scores[game] = updatedScores
        }

        func processAnswer(_ event: Event, connection: Connection) async {
            guard let answer = Int(event.data) else { return }
            if let playerName = connection.playerName, let player = await getPlayers(game: connection.roomCode).first(where: { $0.name == playerName }) {
                var hadCorrectAnswer = false
                if answer == self.currentBattle[connection.roomCode]?.questions[player.name]?.correctAnswer {
                    await self.updateScore(game: connection.roomCode, name: playerName)
                    hadCorrectAnswer = true
                }
                await self.send(game: connection.roomCode, event: Event(type: .answer, data: "\(answer)", playerName: connection.playerName, players: getPlayers(game: connection.roomCode), activeBattle: self.currentBattle[connection.roomCode]))
                
                if hadCorrectAnswer {
                    // self.logger.info("New question")
                    await self.newBattle(connection: connection)
                    guard let battle = self.currentBattle[connection.roomCode] else {
                        return
                    }
                    await self.send(game: connection.roomCode, event: Event(type: .battle, data: Battle.dataString(battle), playerName: connection.playerName, players: getPlayers(game: connection.roomCode), activeBattle: battle))
                }
            }
        }
        
        private func updateBattle(connection: Connection) async {
            if self.previousBattle[connection.roomCode] == nil {
                self.previousBattle[connection.roomCode] = []
            }
            if self.gameModes[connection.roomCode] == nil {
                self.gameModes[connection.roomCode] = .shared
            }
            guard let gameMode = self.gameModes[connection.roomCode] else { return }
            let players = await self.getPlayers(game: connection.roomCode)
            var existingBattle = self.currentBattle[connection.roomCode]
            if existingBattle?.mode == .shared {
                var firstMatch: Question? = existingBattle?.questions.values.first
                if firstMatch == nil {
                    firstMatch = Question()
                }
                for player in await self.getPlayers(game: connection.roomCode) {
                    if existingBattle?.questions[player.name] == nil {
                        existingBattle?.questions[player.name] = firstMatch
                    }
                }
            } else {
                for player in await self.getPlayers(game: connection.roomCode) {
                    if existingBattle?.questions[player.name] == nil {
                        existingBattle?.questions[player.name] = Question()
                    }
                }
            }
//            while let usedCards = self.previousBattle[connection.roomCode], usedCards.contains(possibleQuestion) {
//                possibleQuestion = Battle.new(players: players, mode: gameMode)
//            }
            self.currentBattle[connection.roomCode] = existingBattle
        }
        
        private func newBattle(connection: Connection) async {
            if self.previousBattle[connection.roomCode] == nil {
                self.previousBattle[connection.roomCode] = []
            }
            if self.gameModes[connection.roomCode] == nil {
                self.gameModes[connection.roomCode] = .shared
            }
            guard let gameMode = self.gameModes[connection.roomCode] else { return }
            let players = await self.getPlayers(game: connection.roomCode)
            var possibleQuestion = Battle.new(players: players, mode: gameMode)
//            while let usedCards = self.previousBattle[connection.roomCode], usedCards.contains(possibleQuestion) {
//                possibleQuestion = Battle.new(players: players, mode: gameMode)
//            }
            self.currentBattle[connection.roomCode] = possibleQuestion
        }
        
        private func battleWithCurrent(connection: Connection) async -> Battle? {
            if self.gameModes[connection.roomCode] == nil {
                self.gameModes[connection.roomCode] = .shared
            }
            guard let gameMode = self.gameModes[connection.roomCode] else { return nil }
            let players = await self.getPlayers(game: connection.roomCode)
            let possibleQuestion = Battle.new(players: players, mode: gameMode)
            return possibleQuestion
        }

        func resendQuestion(connection: Connection) async {
            let roomCode = connection.roomCode
            if self.currentBattle[roomCode] == nil {
                logger.info("Creating question with code \(roomCode)")
                
                self.currentBattle[connection.roomCode] = await battleWithCurrent(connection: connection)
            }
            guard let battle = self.currentBattle[roomCode] else {
                logger.info("Failed to return question with code \(roomCode)")
                return }
            await self.updateBattle(connection: connection)
            await self.send(game: connection.roomCode, event: Event(type: .battle, data: Battle.dataString(battle), playerName: connection.playerName, players: getPlayers(game: roomCode), activeBattle: battle))
        }

        func getScores(game: String) async -> [String: Int] {
            return self.scores[game] ?? [:]
        }

        func getPlayers(game: String) async -> [Player] {
            guard let connections = self.gameConnections[game] else {
                return []
            }
            let gameScores = self.scores[game] ?? [:]
            return connections.values.filter {
                $0.playerName != nil }.map { Player(name: $0.playerName!, score: gameScores[$0.playerName!] ?? 0 )}
        }
        
        func resetScores(game: String) async {
            self.scores[game]?.forEach { self.scores[game]?[$0.key] = 0 }
            guard let mode = self.gameModes[game] else { return }
            self.currentBattle[game] = await Battle.new(players: getPlayers(game: game), mode: mode)
            guard let battle = self.currentBattle[game] else {
                return
            }
            await self.send(game: game, event: Event(type: .battle, data: Battle.dataString(battle), playerName: "", players: getPlayers(game: game), activeBattle: battle))
        }

        var gameConnections: [String: [String: Connection]]
//        var outboundConnections: [String: Connection]
        var scores: [String: [String: Int]] = [:]
        var rooms: [String: Date] = [:]
        var gameModes: [String: BattleMode] = [:]
        var currentBattle: [String: Battle] = [:]
        var previousBattle: [String: [Battle]] = [:]
        let logger: Logger
    }

    let connectionStream: AsyncStream<Connection>
    let connectionContinuation: AsyncStream<Connection>.Continuation
    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
        (self.connectionStream, self.connectionContinuation) = AsyncStream<Connection>.makeStream()
    }

    func run() async {
        await withGracefulShutdownHandler {
            await withDiscardingTaskGroup { group in
                let outboundCounnections = OutboundConnections(logger: self.logger)
                for await connection in self.connectionStream {
                    group.addTask {
                        let connectionName = connection.playerName ?? connection.deviceName ?? "unknown"
                        self.logger.info("add connection", metadata: ["name": .string(connectionName)])
                        guard await outboundCounnections.add(game: connection.roomCode, name: connectionName, outbound: connection) else {
                            self.logger.info("user already exists", metadata: ["name": .string(connectionName)])
                            await connection.outbound.send(.close("User connected already"))
                            connection.outbound.finish()
                            return
                        }

                        await outboundCounnections.resendQuestion(connection: connection)

                        do {
                            for try await input in connection.inbound.messages(maxSize: 1_000_000) {
                                guard case .text(let text) = input else { continue }
                                await processInput(text, connection: connection, outboundCounnections: outboundCounnections)
                            }
                        } catch {}

                        self.logger.info("remove connection", metadata: ["name": .string(connectionName)])
                        await outboundCounnections.remove(game: connection.roomCode, name: connectionName)
                        connection.outbound.finish()
                    }
                }
                group.cancelAll()
            }
        } onGracefulShutdown: {
            self.connectionContinuation.finish()
        }
    }
    
    private func processInput(_ input: String, connection: Connection, outboundCounnections: OutboundConnections) async {
        self.logger.debug("Input", metadata: ["message": .string(input)])
        let obj = try? JSONDecoder().decode(Event.self, from: Data(input.utf8))
        guard let obj = obj else { return }
        let output = "[\(connection.playerName ?? connection.deviceName ?? "unknown") (\(connection.roomCode))]: \(obj.data)"
        self.logger.debug("Output", metadata: ["message": .string(output)])
        
        if obj.type == .reset {
            self.logger.info("Reset")
            await outboundCounnections.resetScores(game: connection.roomCode)
        } else if obj.type == .answer {
            await outboundCounnections.processAnswer(obj, connection: connection)
        } else if obj.type == .heartbeat {
            self.logger.info("Heartbeat")
            await outboundCounnections.send(game: connection.roomCode, event: Event(type: .heartbeat, data: "pong!", playerName: connection.playerName, players: outboundCounnections.getPlayers(game: connection.roomCode), activeBattle: outboundCounnections.currentBattle[connection.roomCode]))
        }
    }

    func addUser(name: String, roomCode: String, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter) -> OutputStream? {
        logger.info("Adding user \(name) to room \(roomCode)")
        let outputStream = OutputStream()
        let connection = Connection(playerName: name, deviceName: nil, roomCode: roomCode, inbound: inbound, outbound: outputStream)
        self.connectionContinuation.yield(connection)
        return outputStream
    }

    func addDevice(name: String, roomCode: String, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter) -> OutputStream? {
        logger.info("Adding device \(name) to room \(roomCode)")
        let outputStream = OutputStream()
        let connection = Connection(playerName: nil, deviceName: name, roomCode: roomCode, inbound: inbound, outbound: outputStream)
        self.connectionContinuation.yield(connection)
        return outputStream
    }
    
    func generateCode(strLen: Int = 4) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let resStr = String((0..<strLen).map{_ in chars.randomElement()!})
        return resStr
    }
}
