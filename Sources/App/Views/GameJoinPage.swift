//
//  GameJoinPage.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/21/25.
//

import Elementary

struct GameJoinPage: HTML {
    var roomCode: String? = nil
    
    var content: some HTML {
        div(.class("flex flex-col gap-4")) {
            p {
                "Enter your name to join this game."
            }
            if let roomCode {
                p { "Room code: \(roomCode)"}
            }
            form(.action("/game"), .class("flex flex-col gap-2")) {
                label(.for(String(GameParameterConstants.username.rawValue))) { "Enter your name:" }
                input(.type(.text), .name(String(GameParameterConstants.username.rawValue)), .autofocus)
                    .roundedTextbox()
                if let roomCode {
                    input(.type(.hidden), .name(String(GameParameterConstants.code.rawValue)), .value("\(roomCode)"))
                } else {
                    label(.for(String(GameParameterConstants.code.rawValue))) { "Room code:" }
                    input(.type(.text), .name(String(GameParameterConstants.code.rawValue)), .autofocus)
                        .roundedTextbox()
                }
                
                input(.type(.submit), .class("mt-4"), .value("Let's go!"))
                    .primaryButton()
            }
        }
    }
}
