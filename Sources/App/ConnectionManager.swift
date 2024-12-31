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
    case reset = "reset"
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
    let question: Question?
}

final class Question: Codable {
    let lhs: Int
    let rhs: Int
    let correctAnswer: Int

    init() {
        let lhs = Int.random(in: 1...10)
        let rhs = Int.random(in: 1...4)
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
        let playerName: String?
        let deviceName: String?
        let inbound: WebSocketInboundStream
        let outbound: OutputStream
    }

    actor OutboundConnections {
        init(logger: Logger) {
            self.logger = logger
            self.outboundConnections = [:]
        }

        func send(event: Event) async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(event), let json = String(data: data, encoding: .utf8) else { return }
            for connection in self.outboundConnections.values {
                self.logger.info("Send", metadata: ["user": .string(connection.playerName ?? connection.deviceName ?? "unknown"), "message": .string(json)])
                await connection.outbound.send(.frame(.text(json)))
            }
        }

        func add(name: String, outbound: Connection) async -> Bool {
            guard self.outboundConnections[name] == nil else { return false }
            self.outboundConnections[name] = outbound
            // await self.send("\(name) joined")
            await self.send(event: Event(type: .join, data: name, playerName: name, players: getPlayers(), question: self.question))
            return true
        }

        func remove(name: String) async {
            self.outboundConnections[name] = nil
            // await self.send("\(name) left")
            await self.send(event: Event(type: .leave, data: name, playerName: name, players: getPlayers(), question: self.question))
        }

        func updateScore(name: String) async {
            guard var connection = self.outboundConnections[name] else { return }
            // connection.playerScore = connection.playerScore + 1
            scores[name] = (scores[name] ?? 0) + 1
            await self.send(event: Event(type: .answer, data: name, playerName: name, players: getPlayers(), question: self.question))
        }

        func processAnswer(_ event: Event, connection: Connection) async {
            // self.logger.info("Answer", metadata: ["answer": .string(event.data)])
            guard let answer = Int(event.data) else { return }
            if let playerName = connection.playerName {
                var hadCorrectAnswer = false
                if answer == self.question.correctAnswer {
                    await self.updateScore(name: playerName)
                    hadCorrectAnswer = true
                    // self.logger.info("Correct answer", metadata: ["player": .string(playerName)])
                }
                await self.send(event: Event(type: .answer, data: "\(answer)", playerName: connection.playerName, players: getPlayers(), question: self.question))
                
                if hadCorrectAnswer {
                    // self.logger.info("New question")
                    self.question = Question()
                    await self.send(event: Event(type: .question, data: "\(self.question.lhs) * \(self.question.rhs)", playerName: connection.playerName, players: getPlayers(), question: self.question))
                }
            }
        }

        func resendQuestion(connection: Connection) async {
            await self.send(event: Event(type: .question, data: "\(self.question.lhs) * \(self.question.rhs)", playerName: connection.playerName, players: getPlayers(), question: self.question))
        }

        func getScores() async -> [String: Int] {
            return self.scores
        }

        func getPlayers() async -> [Player] {
            return self.outboundConnections.values.filter { $0.playerName != nil }.map { Player(name: $0.playerName!, score: scores[$0.playerName!] ?? 0) }
        }

        var outboundConnections: [String: Connection]
        var scores: [String: Int] = [:]
        var question: Question = Question()
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
                        guard await outboundCounnections.add(name: connectionName, outbound: connection) else {
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
                        await outboundCounnections.remove(name: connectionName)
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
        let output = "[\(connection.playerName)]: \(obj.data)"
        self.logger.debug("Output", metadata: ["message": .string(output)])
        
        if obj.type == .reset {
            self.logger.info("Reset")
            outboundCounnections.scores.forEach { outboundCounnections.scores[$0.key] = 0 }
            outboundCounnections.question = Question()
            // await outboundCounnections.send(event: Event(type: .reset, data: "reset", playerName: connection.playerName, players: outboundCounnections.getPlayers(), question: outboundCounnections.question))
            await outboundCounnections.send(event: Event(type: .question, data: "\(self.question.lhs) * \(self.question.rhs)", playerName: connection.playerName, players: getPlayers(), question: self.question))
        } else if obj.type == .answer {
            await outboundCounnections.processAnswer(obj, connection: connection)
        } else if obj.type == .heartbeat {
            self.logger.info("Heartbeat")
            let scores = await outboundCounnections.getScores()
            await outboundCounnections.send(event: Event(type: .heartbeat, data: "pong!", playerName: connection.playerName, players: outboundCounnections.getPlayers(), question: outboundCounnections.question))
        }
    }

    func addUser(name: String, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter) -> OutputStream {
        let outputStream = OutputStream()
        let connection = Connection(playerName: name, deviceName: nil, inbound: inbound, outbound: outputStream)
        self.connectionContinuation.yield(connection)
        return outputStream
    }

    func addDevice(name: String, inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter) -> OutputStream {
        let outputStream = OutputStream()
        let connection = Connection(playerName: nil, deviceName: name, inbound: inbound, outbound: outputStream)
        self.connectionContinuation.yield(connection)
        return outputStream
    }
}
