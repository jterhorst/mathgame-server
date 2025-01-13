//
//  Question.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/12/25.
//

import Foundation

final class Question: Codable, Equatable, ObservableObject {
    static func == (lhs: Question, rhs: Question) -> Bool {
        lhs.lhs == rhs.lhs && lhs.rhs == rhs.rhs
    }
    
    let lhs: Int
    let rhs: Int
    let correctAnswer: Int

    init() {
        let lhs = Int.random(in: 1...11)
        let rhs = Int.random(in: 1...4)
        let flipped = Int.random(in: 0...100) % 2 == 0
        let correctAnswer = lhs * rhs
        self.lhs = flipped ? lhs : rhs
        self.rhs = flipped ? rhs : lhs
        self.correctAnswer = correctAnswer
    }
}
