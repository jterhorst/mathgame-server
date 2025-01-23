//
//  GamePlayPage.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/21/25.
//

import Elementary

struct CardView: HTML {
//    var question: Question
    var answer: String = "?"
    
    var content: some HTML {
        div(.class("bg-zinc-50 m-6 p-5 rounded-lg shadow-md font-sans text-2xl font-bold")) {
            div(.class("m-5")) {
                p(.id("math_problem_lhs"), .class("text-right")) {
                    "--"
                }
                p(.id("math_problem_rhs"), .class("text-right")) {
                    "x --"
                }
            }
            div(.class("mt-4 ml-0 mr-0 w-full h-2 bg-black")) {
                " "
            }
            div(.class("mt-5 text-center w-full h-10")) {
                input(.id("input"), .on(.change, "inputEnter()"), .class("w-10 text-center border-none bg-transparent"), .type(.text), .name(String(GameParameterConstants.code.rawValue)), .placeholder("?"), .autofocus)
            }
        }
    }
}

//struct PlayersView: HTML {
//    var players: [Player]
//    var currentPlayer: String
//    
//    var content: some HTML {
//        div(.class("gap-4")) {
//            p {
//                "Scores:"
//            }
//            ul {
//                for player in players {
//                    if player.name == currentPlayer {
//                        li(.class("font-bold")) {
//                            "\(player.name) - \(player.score)"
//                        }
//                    } else {
//                        li {
//                            "\(player.name) - \(player.score)"
//                        }
//                    }
//                }
//            }
//        }
//    }
//}

struct GamePlayPage: HTML {
    var name: String?
    var roomCode: String?
    
    var contentWidth: String {
#if DEBUG
      "float-left w-1/2"
#else
      "w-full"
#endif
    }
    
    var happyPathContent: some HTML {
        div {
            div(.class(contentWidth)) {
                div {
                    p {
                        "Room code: \(roomCode ?? "")"
                    }
                    input(.id("room_entry"), .type(.hidden), .name("room_entry"), .value("\(roomCode ?? "")"))
                    input(.id("name_entry"), .type(.hidden), .name("name_entry"), .value("\(name ?? "")"))
                }
                div {
                    p(.id("timer_remaining")) {
                        "--"
                    }
                }
                CardView()
    //            PlayersView(players: [Player(name: "Bob", score: 5), Player(name: "John", score: 2)], currentPlayer: name ?? "")
                div(.id("players_list")) {
                    ul {
                        
                    }
                }
                if name == nil {
                    div {
                        p {
                            "Join this game at mathbattle.tv"
                        }
                    }
                }
            }
#if DEBUG
            div(.id("output_box"), .class("float-right w-1/2 text-xs")) {
                p {
                    "---"
                }
            }
#endif
            div(.class("clear-both")) {
                p { "" }
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
