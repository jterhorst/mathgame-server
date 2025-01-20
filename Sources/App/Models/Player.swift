//
//  Player.swift
//  Math Game Client
//
//  Created by Jason Terhorst on 1/7/25.
//

import Foundation

enum PlayerType: Codable {
    case parent
    case student
}

struct Player: Codable, Hashable {
    let name: String
    var score: Int
    var type: PlayerType = .student
}
