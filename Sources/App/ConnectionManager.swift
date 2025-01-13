
import AsyncAlgorithms
import Hummingbird
import HummingbirdWebSocket
import Logging
import NIOConcurrencyHelpers
import ServiceLifecycle
import Foundation

enum EventTypes: String, Codable {
    case join = "join"
    case leave = "leave"
    case question = "question"
    case answer = "answer"
    case heartbeat = "heartbeat"
    case reset = "reset"
}

struct Player: Codable, Equatable {
    let name: String
    var score: Int
}

struct Event: Codable, Equatable {
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.type == rhs.type && lhs.data == rhs.data
    }
    
    let type: EventTypes
    let data: String
    let playerName: String?
    let players: [Player]?
    let question: Question?
}

final class Question: Codable, Equatable, ObservableObject {
    static func == (lhs: Question, rhs: Question) -> Bool {
        lhs.lhs == rhs.lhs && lhs.rhs == rhs.rhs
    }
    
    let lhs: Int
    let rhs: Int
    let correctAnswer: Int

    init() {
        let lhs = Int.random(in: 1...11)
        let rhs = Int.random(in: 1...4)
        let flipped = Int.random(in: 0...100) % 2 == 0
        let correctAnswer = lhs * rhs
        self.lhs = flipped ? lhs : rhs
        self.rhs = flipped ? rhs : lhs
        self.correctAnswer = correctAnswer
    }
}

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
            await self.send(game: game, event: Event(type: .join, data: name, playerName: name, players: getPlayers(game: game), question: self.currentQuestion[game]))
            return true
        }

        func remove(game: String, name: String) async {
            self.gameConnections[game]?[name] = nil
            self.scores[game]?[name] = nil
            // await self.send("\(name) left")
            await self.send(game: game, event: Event(type: .leave, data: name, playerName: name, players: getPlayers(game: game), question: self.currentQuestion[game]))
        }

        func updateScore(game: String, name: String) async {
            var updatedScores = scores[game] ?? [:]
            updatedScores[name] = (updatedScores[name] ?? 0) + 1
            await self.send(game: game, event: Event(type: .answer, data: name, playerName: name, players: getPlayers(game: game), question: self.currentQuestion[game]))
            self.scores[game] = updatedScores
        }

        func processAnswer(_ event: Event, connection: Connection) async {
            // self.logger.info("Answer", metadata: ["answer": .string(event.data)])
            guard let answer = Int(event.data) else { return }
            if let playerName = connection.playerName {
                var hadCorrectAnswer = false
                if answer == self.currentQuestion[connection.roomCode]?.correctAnswer {
                    await self.updateScore(game: connection.roomCode, name: playerName)
                    hadCorrectAnswer = true
                    // self.logger.info("Correct answer", metadata: ["player": .string(playerName)])
                }
                await self.send(game: connection.roomCode, event: Event(type: .answer, data: "\(answer)", playerName: connection.playerName, players: getPlayers(game: connection.roomCode), question: self.currentQuestion[connection.roomCode]))
                
                if hadCorrectAnswer {
                    // self.logger.info("New question")
                    self.newQuestion(connection: connection)
                    guard let question = self.currentQuestion[connection.roomCode] else {
                        return
                    }
                    await self.send(game: connection.roomCode, event: Event(type: .question, data: "\(question.lhs) * \(question.rhs)", playerName: connection.playerName, players: getPlayers(game: connection.roomCode), question: question))
                }
            }
        }
        
        private func newQuestion(connection: Connection) {
            if self.previousQuestions[connection.roomCode] == nil {
                self.previousQuestions[connection.roomCode] = []
            }
            var possibleQuestion = Question()
            while let usedCards = self.previousQuestions[connection.roomCode], usedCards.contains(possibleQuestion) {
                possibleQuestion = Question()
            }
            self.currentQuestion[connection.roomCode] = possibleQuestion
        }

        func resendQuestion(connection: Connection) async {
            let roomCode = connection.roomCode
            if self.currentQuestion[roomCode] == nil {
                logger.info("Creating question with code \(roomCode)")
                self.currentQuestion[roomCode] = Question()
            }
            guard let question = self.currentQuestion[roomCode] else {
                logger.info("Failed to return question with code \(roomCode)")
                return }
            await self.send(game: roomCode, event: Event(type: .question, data: "\(question.lhs) * \(question.rhs)", playerName: connection.playerName, players: getPlayers(game: roomCode), question: question))
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
            self.currentQuestion[game] = Question()
            guard let question = self.currentQuestion[game] else {
                return
            }
            await self.send(game: game, event: Event(type: .question, data: "\(question.lhs) * \(question.rhs)", playerName: "", players: getPlayers(game: game), question: question))
        }

        var gameConnections: [String: [String: Connection]]
//        var outboundConnections: [String: Connection]
        var scores: [String: [String: Int]] = [:]
        var rooms: [String: Date] = [:]
        var currentQuestion: [String: Question] = [:]
        var previousQuestions: [String: [Question]] = [:]
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
            await outboundCounnections.send(game: connection.roomCode, event: Event(type: .heartbeat, data: "pong!", playerName: connection.playerName, players: outboundCounnections.getPlayers(game: connection.roomCode), question: outboundCounnections.currentQuestion[connection.roomCode]))
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
