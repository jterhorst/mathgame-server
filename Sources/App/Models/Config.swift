//
//  Config.swift
//  Math Game Client
//
//  Created by Jason Terhorst on 1/7/25.
//

struct Config {
    private static let devMode = true
    
    static var host: String {
        devMode ? "ws://127.0.0.1:8080" : "wss://mathbattle.tv"
    }
    
    // how long do we go until the game runs out?
    static let maxScore: Int = 30
    
    // how long for each question?
    static let maxTime: Int = 20
    
    // how long do we add to handicap adults to avoid kids meltdown? (Implemented as subtraction from timer)
    static let parentPenaltyTime: Int = 10
}
