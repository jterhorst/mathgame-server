//
//  Player.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/12/25.
//

import Foundation

struct Player: Codable, Equatable {
    let name: String
    var score: Int
}
