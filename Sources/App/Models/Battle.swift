//
//  Battle.swift
//  Math Game Client
//
//  Created by Jason Terhorst on 1/16/25.
//

import Foundation

enum BattleMode: Codable {
    case shared // All players solve the same question
    case speedTrial // Each player has a stack, and it's first to the finish
}

struct Battle: Codable, Equatable {
    let questions: [Player: Question]
    let mode: BattleMode
    
    static func dataString(_ battle: Battle) -> String {
        do {
            return String(data: try JSONEncoder().encode(battle), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    static func new(players: [Player], mode: BattleMode) -> Battle {
        var playersDict: [Player: Question] = [:]
        let sharedQuestion = Question()
        for player in players {
            playersDict[player] = (mode == .shared) ? sharedQuestion : Question()
        }
        return Battle(questions: playersDict, mode: mode)
    }
}
