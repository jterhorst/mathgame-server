//
//  MainLayout.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/21/25.
//

import Elementary
import Foundation

extension MainLayout: Sendable where Body: Sendable {}
struct MainLayout<Body: HTML>: HTMLDocument {
    var title: String
    @HTMLBuilder var pageContent: Body

    var head: some HTML {
        meta(.charset(.utf8))
        meta(.name(.viewport), .content("width=device-width, initial-scale=1.0"))
        HTMLComment("Do not use this in production, use the tailwind CLI to generate a production build from your swift files.")
        script(.src("https://cdn.tailwindcss.com")) {}
        
    }

    var body: some HTML {
        div(.class("flex flex-col min-h-screen items-center font-mono bg-zinc-300")) {
            div(.class("bg-zinc-50 m-12 p-12 rounded-lg shadow-md gap-4")) {
                h1(.class("text-3xl pb-6 mx-auto")) { title }
                main {
                    pageContent
                }
            }
        }
    }
}

struct GamePlayLayout<Body: HTML>: HTMLDocument {
    var title: String
    @HTMLBuilder var pageContent: Body

    var head: some HTML {
        meta(.charset(.utf8))
        meta(.name(.viewport), .content("width=device-width, initial-scale=1.0"))
        HTMLComment("Do not use this in production, use the tailwind CLI to generate a production build from your swift files.")
        script(.src("https://cdn.tailwindcss.com")) {}
        script(.src("/game.js?cachebuster=\(Date().timeIntervalSince1970)")) {}
    }

    var body: some HTML {
        div(.class("flex flex-col min-h-screen items-center font-mono bg-zinc-300")) {
            div(.class("m-12 p-12 gap-4")) {
                main {
                    pageContent
                }
            }
        }
    }
}
