//
//  GamePlayPage.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/21/25.
//

import Elementary

struct CardView: HTML {
    var question: Question
    var answer: String = "?"
    
    var content: some HTML {
        div(.class("bg-zinc-50 m-6 p-5 rounded-lg shadow-md font-sans text-2xl font-bold")) {
            div(.class("m-5")) {
                p(.class("text-right")) {
                    "\(question.lhs)"
                }
                p(.class("text-right")) {
                    "x \(question.rhs)"
                }
            }
            div(.class("mt-4 ml-0 mr-0 w-full h-2 bg-black")) {
                " "
            }
            div(.class("mt-5 text-center w-full h-10")) {
                input(.class("w-10 text-center border-none bg-transparent"), .type(.text), .name(String(GameParameterConstants.code.rawValue)), .placeholder("?"), .autofocus)
            }
        }
    }
}

struct PlayersView: HTML {
    var players: [Player]
    var currentPlayer: String
    
    var content: some HTML {
        div(.class("gap-4")) {
            p {
                "Scores:"
            }
            ul {
                for player in players {
                    if player.name == currentPlayer {
                        li(.class("font-bold")) {
                            "\(player.name) - \(player.score)"
                        }
                    } else {
                        li {
                            "\(player.name) - \(player.score)"
                        }
                    }
                }
            }
        }
    }
}

struct GamePlayPage: HTML {
    var name: String?
    var roomCode: String?
    
    var happyPathContent: some HTML {
        div(.class("block")) {
            div(.class("block")) {
                p {
                    "Room code: \(roomCode ?? "")"
                }
            }
            CardView(question: Question())
            PlayersView(players: [Player(name: "Bob", score: 5), Player(name: "John", score: 2)], currentPlayer: name ?? "")
            if name == nil {
                div(.class("block")) {
                    p {
                        "Join this game at mathbattle.tv"
                    }
                }
            }
        }
    }
    
    var sadPathContent: some HTML {
        p { "No player name or room code provided. Please go back and enter your details to play."}
    }
    
    var content: some HTML {
        div(.class("gap-4")) {
            if let name, let roomCode {
                happyPathContent
            } else {
                sadPathContent
            }
        }
    }
}
