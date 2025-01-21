//
//  BrowserSync.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/20/25.
//

import Foundation

#if DEBUG
func browserSyncReload() {
    let p = Process()
    p.executableURL = URL(string: "file:///bin/sh")
    p.arguments = ["-c", "browser-sync reload"]
    do {
        try p.run()
    } catch {
        print("Could not auto-reload: \(error)")
    }
}
#endif
