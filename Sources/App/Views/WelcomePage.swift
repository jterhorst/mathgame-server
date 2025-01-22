//
//  WelcomePage.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/21/25.
//

import Elementary

struct WelcomePage: HTML {
    var content: some HTML {
        div(.class("flex flex-col gap-4")) {
            p {
                "This is a basic prototype of a math game."
            }
            p {
                a(.href("/play"), .class("text-blue-700")) {
                    "Join a game"
                }
                " | "
                a(.href("/create"), .class("text-blue-700")) {
                    "Create a game"
                }
            }
        }
    }
}
