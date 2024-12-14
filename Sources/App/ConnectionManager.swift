//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2021 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

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
}

struct Player: Codable {
    let name: String
    var score: Int
}

struct Event: Codable {
    let type: EventTypes
    let data: String
    let playerName: String?
    let players: [Player]?
}

class Question: Codable {
    var lhs: Int
    var rhs: Int
    var correctAnswer: Int

    init() {
        let lhs = Int.random(in: 1...10)
        let rhs = Int.random(in: 1...10)
        let correctAnswer = lhs * rhs
        self.lhs = lhs
        self.rhs = rhs
        self.correctAnswer = correctAnswer
    }

    func update() {
        let lhs = Int.random(in: 1...10)
        let rhs = Int.random(in: 1...10)
        let correctAnswer = lhs * rhs
        self.lhs = lhs
        self.rhs = rhs
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
        let playerName: String
        var playerScore: Int
        let inbound: WebSocketInboundStream
        let outbound: OutputStream
    }

    actor OutboundConnections {
        init() {
            self.outboundConnections = [:]
        }

        func send(event: Event) async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(event), let json = String(data: data, encoding: .utf8) else { return }
            for connection in self.outboundConnections.values {
                await connection.outbound.send(.frame(.text(json)))
            }
        }

        func add(name: String, outbound: Connection) async -> Bool {
            guard self.outboundConnections[name] == nil else { return false }
            self.outboundConnections[name] = outbound
            // await self.send("\(name) joined")
            await self.send(event: Event(type: .join, data: name, playerName: name, players: self.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
            return true
        }

        func remove(name: String) async {
            self.outboundConnections[name] = nil
            // await self.send("\(name) left")
            await self.send(event: Event(type: .leave, data: name, playerName: name, players: self.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
        }

        func updateScore(name: String) async {
            guard var connection = self.outboundConnections[name] else { return }
            connection.playerScore = connection.playerScore + 1
            await self.send(event: Event(type: .answer, data: name, playerName: name, players: self.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
        }

        var outboundConnections: [String: Connection]
    }

    let connectionStream: AsyncStream<Connection>
    let connectionContinuation: AsyncStream<Connection>.Continuation
    let logger: Logger
    var question: Question = Question()

    init(logger: Logger) {
        self.logger = logger
        (self.connectionStream, self.connectionContinuation) = AsyncStream<Connection>.makeStream()
    }

    func run() async {
        await withGracefulShutdownHandler {
            await withDiscardingTaskGroup { group in
                var outboundCounnections = OutboundConnections()
                for await connection in self.connectionStream {
                    group.addTask {
                        self.logger.info("add connection", metadata: ["name": .string(connection.playerName)])
                        guard await outboundCounnections.add(name: connection.playerName, outbound: connection) else {
                            self.logger.info("user already exists", metadata: ["name": .string(connection.playerName)])
                            await connection.outbound.send(.close("User connected already"))
                            connection.outbound.finish()
                            return
                        }

                        await resendQuestion(connection: connection, outboundConnections: &outboundCounnections)

                        do {
                            for try await input in connection.inbound.messages(maxSize: 1_000_000) {
                                guard case .text(let text) = input else { continue }
                                await processInput(text, connection: connection, outboundCounnections: &outboundCounnections)
                            }
                        } catch {}

                        self.logger.info("remove connection", metadata: ["name": .string(connection.playerName)])
                        await outboundCounnections.remove(name: connection.playerName)
                        connection.outbound.finish()
                    }
                }
                group.cancelAll()
            }
        } onGracefulShutdown: {
            self.connectionContinuation.finish()
        }
    }
    
    private func processInput(_ input: String, connection: Connection, outboundCounnections: inout OutboundConnections) async {
        self.logger.debug("Input", metadata: ["message": .string(input)])
        let obj = try? JSONDecoder().decode(Event.self, from: Data(input.utf8))
        guard let obj = obj else { return }
        let output = "[\(connection.playerName)]: \(obj.data)"
        self.logger.debug("Output", metadata: ["message": .string(output)])
        
        // guard obj.type == .answer else { return }
        if obj.type == .answer {
            await processAnswer(obj, connection: connection, outboundCounnections: &outboundCounnections)
        } else if obj.type == .heartbeat {
            self.logger.info("Heartbeat")
            await outboundCounnections.send(event: Event(type: .heartbeat, data: "pong!", playerName: connection.playerName, players: outboundCounnections.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
        }
        
        // await outboundCounnections.send(event: Event(type: <#T##EventTypes#>, data: <#T##String#>))
    }

    private func resendQuestion(connection: Connection, outboundConnections: inout OutboundConnections) async {
        await outboundConnections.send(event: Event(type: .question, data: "\(self.question.lhs) * \(self.question.rhs)", playerName: connection.playerName, players: outboundConnections.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
    }

    private func processAnswer(_ event: Event, connection: Connection, outboundCounnections: inout OutboundConnections) async {
        self.logger.info("Answer", metadata: ["answer": .string(event.data)])
        guard let answer = Int(event.data) else { return }
        let playerName = connection.playerName
        
        var hadCorrectAnswer = false
        if answer == self.question.correctAnswer {
            await outboundCounnections.updateScore(name: playerName)
            hadCorrectAnswer = true
            self.logger.info("Correct answer", metadata: ["player": .string(playerName)])
        }
        await outboundCounnections.send(event: Event(type: .answer, data: "\(answer)", playerName: connection.playerName, players: outboundCounnections.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
        
        if hadCorrectAnswer {
            self.logger.info("New question")
            self.question.update()
            await outboundCounnections.send(event: Event(type: .question, data: "\(self.question.lhs) * \(self.question.rhs)", playerName: connection.playerName, players: outboundCounnections.outboundConnections.values.map { Player(name: $0.playerName, score: $0.playerScore) }))
        }
    }

    func addUser(name: String, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter) -> OutputStream {
        let outputStream = OutputStream()
        let connection = Connection(playerName: name, playerScore: 0, inbound: inbound, outbound: outputStream)
        self.connectionContinuation.yield(connection)
        return outputStream
    }
}
