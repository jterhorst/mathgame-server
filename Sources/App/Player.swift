//
//  Player.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/12/25.
//

import Foundation

enum PlayerType: Codable {
    case parent
    case student
}

struct Player: Codable {
    let name: String
    var score: Int
    var type: PlayerType = .student
}
