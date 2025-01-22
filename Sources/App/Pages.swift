//
//  Pages.swift
//  mathgame-server
//
//  Created by Jason Terhorst on 1/20/25.
//

import Elementary

// example of using modifier-like methods to apply styling
extension input {
    // making the return type specify the input tag allows to chain attributes for it
    func roundedTextbox() -> some HTML<HTMLTag.input> {
        attributes(.class("rounded-lg p-2 border border-gray-300"))
    }

    func primaryButton() -> some HTML<HTMLTag.input> {
        attributes(
            .class("rounded-lg p-2 bg-blue-500 text-white font-semibold shadow-sm"),
            .class("hover:bg-blue-600 hover:shadow-xl")
        )
    }
}

enum EnvironmentValues {
    @TaskLocal static var name: String?
}
