//
//  LilDocApp.swift
//  LilDoc
//
//  Created by Adam Keys on 1/31/26.
//

import SwiftUI

@main
struct LilDocApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LilDocDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
