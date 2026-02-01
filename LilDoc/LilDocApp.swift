//
//  LilDocApp.swift
//  LilDoc
//
//  Created by Adam Keys on 1/31/26.
//

import SwiftUI

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
}

@main
struct LilDocApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LilDocDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 680, height: 420)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
