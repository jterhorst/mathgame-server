//
//  EventTypes.swift
//  Math Game Client
//
//  Created by Jason Terhorst on 1/7/25.
//

import Foundation

enum EventTypes: String, Codable {
    case join = "join"
    case leave = "leave"
    case battle = "battle"
    case answer = "answer"
    case heartbeat = "heartbeat"
    case reset = "reset"
    case timerTick = "tick"
    case timeExpired = "time_up"
    case gameEnd = "game_end"
}
