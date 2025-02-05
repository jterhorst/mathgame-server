@testable import App
import Hummingbird
import HummingbirdTesting
import HummingbirdWSClient
import HummingbirdWSTesting
import NIOWebSocket
import XCTest

final class AppTests: XCTestCase {
    struct TestArguments: AppArguments {
        let hostname = "localhost"
        let port = 8080
    }

    func testUpgradeFail() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            do {
                _ = try await client.ws("/game") { inbound, outbound, context in
                    XCTFail("Upgrade failed so shouldn't get here")
                }
            } catch let error as WebSocketClientError where error == .webSocketUpgradeFailed {}
        }
    }
    
    enum CustomError: Error {
        case unknown
    }

    private func event(for frame: WebSocketMessage) throws -> Event? {
        switch frame {
        case .text(let text):
            print("text : \(text)")
            if let data = text.data(using: .utf8) {
                let event = try JSONDecoder().decode(Event.self, from: data)
                return event
            }
        default:
            XCTFail()
        }
        return nil
    }
    
    func verifyJoin(event: Event, playerName: String) {
        XCTAssertEqual(event.type, .join)
        XCTAssertEqual(event.data, playerName)
    }
    
    func verifyQuestion(question: Question) {
        XCTAssertEqual(question.correctAnswer, (question.lhs * question.rhs))
    }
    
    func verifyQuestions(event: Event) throws {
        XCTAssertEqual(event.type, .battle)
        let questions: [Question] = try XCTUnwrap(event.activeBattle).questions.values.shuffled()
        for question in questions {
            verifyQuestion(question: question)
        }
    }
    
    func verifyPlayers(event: Event, expectedPlayerNames: [String]) throws {
        guard let players = event.players else {
            XCTFail()
            return
        }
        print("players: \(players)")
        for name in expectedPlayerNames {
            XCTAssertTrue(players.contains(where: { player in
                player.name == name
            }))
        }
    }
    
    func verifyTimerTick(event: Event) throws -> Int {
        print("testing timer event \(event)")
        XCTAssertTrue(event.type == .timerTick)
        XCTAssertNotNil(event.answerTimeRemaining)
        return event.answerTimeRemaining ?? 0
    }
    
    func testHello() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            let roomCode = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode)
            print("resulting code: \(roomCode)")
            _ = try await client.ws("/game?code=\(roomCode)&user=john") { inbound, outbound, context in
                
                var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()
                let joinEvent = try await self.event(for: inboundIterator.next()!)!
                self.verifyJoin(event: joinEvent, playerName: "john")
                let questionEvent = try await self.event(for: inboundIterator.next()!)!
                try self.verifyQuestions(event: questionEvent)
            }
        }
    }

    func testTwoClients() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            let roomCode = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode)
            print("resulting code: \(roomCode)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try await client.ws("/game?code=\(roomCode)&user=john") { inbound, outbound, context in
                        
                        var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()
                        let joinEvent = try await self.event(for: inboundIterator.next()!)!
                        self.verifyJoin(event: joinEvent, playerName: "john")
                        try self.verifyPlayers(event: joinEvent, expectedPlayerNames: ["john"])
                        let questionEvent = try await self.event(for: inboundIterator.next()!)!
                        try self.verifyQuestions(event: questionEvent)
                        
                        sleep(2) // Wait! Don't let John disconnect yet! Jane needs to see both of them on the player list.
                    }
                }
                group.addTask {
                    // add stall to ensure john joins first
                    try await Task.sleep(for: .milliseconds(100))
                    _ = try await client.ws("/game?code=\(roomCode)&user=jane") { inbound, outbound, context in
                        
                        var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()

                        let joinEvent = try await self.event(for: inboundIterator.next()!)!
                        self.verifyJoin(event: joinEvent, playerName: "jane")
                        try self.verifyPlayers(event: joinEvent, expectedPlayerNames: ["john", "jane"])
                        let questionEvent = try await self.event(for: inboundIterator.next()!)!
                        try self.verifyQuestions(event: questionEvent)
                        try self.verifyPlayers(event: questionEvent, expectedPlayerNames: ["john", "jane"])
                    }
                }
                try await group.next()
                try await group.next()
            }
        }
    }

    func testNameClash() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            let roomCode = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode)
            print("resulting code: \(roomCode)")
            try await withThrowingTaskGroup(of: NIOWebSocket.WebSocketErrorCode?.self) { group in
                group.addTask {
                    return try await client.ws("/game?code=\(roomCode)&user=john") { inbound, outbound, context in
                        try await Task.sleep(for: .milliseconds(200))
                    }?.closeCode
                }
                group.addTask {
                    return try await client.ws("/game?code=\(roomCode)&user=john") { inbound, outbound, context in
                        try await Task.sleep(for: .milliseconds(200))
                    }?.closeCode
                }
                let rt1 = try await group.next()
                print("first result: \(String(describing: rt1))")
                let rt2 = try await group.next()
                print("second result: \(String(describing: rt2))")
                XCTAssert(rt1 == .unexpectedServerError || rt2 == .unexpectedServerError)
            }
        }
    }
    
    func testGenerateCode() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            _ = try await client.execute(uri: "/new_game", method: .get) { response in
//                print("response: \(response)")
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
            }
        }
    }
    
    func testTwoGamesClients() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            let roomCode1 = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode1)
            let roomCode2 = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode2)
            print("resulting code: \(roomCode1)")
            print("resulting code: \(roomCode2)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try await client.ws("/game?code=\(roomCode1)&user=john") { inbound, outbound, context in
                        
                        var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()
                        let joinEvent = try await self.event(for: inboundIterator.next()!)!
                        self.verifyJoin(event: joinEvent, playerName: "john")
                        try self.verifyPlayers(event: joinEvent, expectedPlayerNames: ["john"])
                        let questionEvent = try await self.event(for: inboundIterator.next()!)!
                        try self.verifyQuestions(event: questionEvent)
                        
                        sleep(2) // Wait! Don't let John disconnect yet! Jane needs to see both of them on the player list.
                    }
                }
                group.addTask {
                    // add stall to ensure john joins first
                    try await Task.sleep(for: .milliseconds(100))
                    _ = try await client.ws("/game?code=\(roomCode2)&user=jane") { inbound, outbound, context in
                        
                        var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()

                        let joinEvent = try await self.event(for: inboundIterator.next()!)!
                        self.verifyJoin(event: joinEvent, playerName: "jane")
                        try self.verifyPlayers(event: joinEvent, expectedPlayerNames: ["jane"])
                        let questionEvent = try await self.event(for: inboundIterator.next()!)!
                        try self.verifyQuestions(event: questionEvent)
                        try self.verifyPlayers(event: questionEvent, expectedPlayerNames: ["jane"])
                    }
                }
                try await group.next()
                try await group.next()
            }
        }
    }

    func testNamesDontClashOnDifferentGames() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            let roomCode1 = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode1)
            print("resulting code: \(roomCode1)")
            let roomCode2 = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode2)
            print("resulting code: \(roomCode2)")
            try await withThrowingTaskGroup(of: NIOWebSocket.WebSocketErrorCode?.self) { group in
                group.addTask {
                    return try await client.ws("/game?code=\(roomCode1)&user=john") { inbound, outbound, context in
                        try await Task.sleep(for: .milliseconds(100))
                    }?.closeCode
                }
                group.addTask {
                    return try await client.ws("/game?code=\(roomCode2)&user=john") { inbound, outbound, context in
                        try await Task.sleep(for: .milliseconds(100))
                    }?.closeCode
                }
                let rt1 = try await group.next()
                let rt2 = try await group.next()
                XCTAssertFalse(rt1 == .unexpectedServerError || rt2 == .unexpectedServerError)
            }
        }
    }
    
    func testTimerTick() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.live) { client in
            let roomCode = try await client.execute(uri: "/new_game", method: .get) { response in
                let json = try JSONDecoder().decode([String: String].self, from: response.body)
                XCTAssertTrue(json["code"] != nil)
                XCTAssertTrue(json["code"]?.count == 4)
                print("code: \(String(describing: json["code"]))")
                return json["code"]
            }!
            XCTAssertNotNil(roomCode)
            print("resulting code: \(roomCode)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try await client.ws("/game?code=\(roomCode)&user=john") { inbound, outbound, context in
                        
                        var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()
                        let joinEvent = try await self.event(for: inboundIterator.next()!)!
                        self.verifyJoin(event: joinEvent, playerName: "john")
                        try self.verifyPlayers(event: joinEvent, expectedPlayerNames: ["john"])
                        let questionEvent = try await self.event(for: inboundIterator.next()!)!
                        try self.verifyQuestions(event: questionEvent)
                        
                        
                        var lastResult = NSIntegerMax
                        for n in 0...3 {
                            let event = try await self.event(for: inboundIterator.next()!)!
                            if event.type == .timerTick {
                                let result = try self.verifyTimerTick(event: event)
                                if result > 0 {
                                    print("\(n) tick \(result)")
                                    XCTAssertLessThan(result, lastResult)
                                    lastResult = result
                                }
                            }
                        }
                        
                        sleep(2) // Wait! Don't let John disconnect yet! Jane needs to see both of them on the player list.
                        
                    }
                }
                group.addTask {
                    // add stall to ensure john joins first
                    try await Task.sleep(for: .milliseconds(100))
                    _ = try await client.ws("/game?code=\(roomCode)&user=jane") { inbound, outbound, context in
                        
                        var inboundIterator = inbound.messages(maxSize: 1 << 16).makeAsyncIterator()

                        let joinEvent = try await self.event(for: inboundIterator.next()!)!
                        self.verifyJoin(event: joinEvent, playerName: "jane")
                        try self.verifyPlayers(event: joinEvent, expectedPlayerNames: ["john", "jane"])
                        let questionEvent = try await self.event(for: inboundIterator.next()!)!
                        try self.verifyQuestions(event: questionEvent)
                        try self.verifyPlayers(event: questionEvent, expectedPlayerNames: ["john", "jane"])
                        
                        var lastResult = NSIntegerMax
                        for n in 0...3 {
                            let event = try await self.event(for: inboundIterator.next()!)!
                            if event.type == .timerTick {
                                let result = try self.verifyTimerTick(event: event)
                                if result > 0 {
                                    print("\(n) tock \(result)")
                                    XCTAssertLessThan(result, lastResult)
                                    lastResult = result
                                }
                            }
                        }
                    }
                }
                try await group.next()
                try await group.next()
            }
        }
    }
}
