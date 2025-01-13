//
//  Event.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/12/25.
//

import Foundation

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
