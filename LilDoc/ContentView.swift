//
//  ContentView.swift
//  LilDoc
//
//  Created by Adam Keys on 1/31/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: LilDocDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(LilDocDocument()))
}
