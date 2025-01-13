//
//  EventTypes.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/12/25.
//

import Foundation

enum EventTypes: String, Codable {
    case join = "join"
    case leave = "leave"
    case question = "question"
    case answer = "answer"
    case heartbeat = "heartbeat"
    case reset = "reset"
    case timerTick = "tick"
}
