//
//  LilDocApp.swift
//  LilDoc
//
//  Created by Adam Keys on 1/31/26.
//

import SwiftUI
import AppKit

@main
struct LilDocApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LilDocDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 680, height: 420)
        .commands {
            CommandGroup(after: .textEditing) {
                Divider()

                Button("Find...") { sendFind(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace...") { sendFind(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Find Next") { sendFind(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") { sendFind(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Use Selection for Find") { sendFind(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }

    private func sendFind(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(
            #selector(NSTextView.performFindPanelAction(_:)),
            to: nil,
            from: item
        )
    }
}
