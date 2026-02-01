//
//  ContentView.swift
//  LilDoc
//
//  Created by Adam Keys on 1/31/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Binding var document: LilDocDocument
    @State private var searchText = ""
    @State private var currentMatchIndex = 0
    @State private var matchCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HighlightingTextEditor(
                text: $document.text,
                searchText: searchText,
                currentMatchIndex: $currentMatchIndex,
                matchCount: $matchCount
            )
            
            Divider()
            
            HStack(spacing: 8) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 200)
                
                if !searchText.isEmpty && matchCount > 0 {
                    Text("\(currentMatchIndex + 1) of \(matchCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: previousMatch) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(searchText.isEmpty || matchCount == 0)
                
                Button(action: nextMatch) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("g", modifiers: .command)
                .disabled(searchText.isEmpty || matchCount == 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    private func previousMatch() {
        if matchCount > 0 {
            currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        }
    }
    
    private func nextMatch() {
        if matchCount > 0 {
            currentMatchIndex = (currentMatchIndex + 1) % matchCount
        }
    }
}

struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var searchText: String
    @Binding var currentMatchIndex: Int
    @Binding var matchCount: Int
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        
        applyHighlighting(to: textView, context: context)
    }
    
    private func applyHighlighting(to textView: NSTextView, context: Context) {
        guard let textStorage = textView.textStorage else { return }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        
        guard !searchText.isEmpty else {
            DispatchQueue.main.async {
                matchCount = 0
                currentMatchIndex = 0
            }
            return
        }
        
        let content = textView.string as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: content.length)
        
        while searchRange.location < content.length {
            let foundRange = content.range(
                of: searchText,
                options: .caseInsensitive,
                range: searchRange
            )
            if foundRange.location == NSNotFound { break }
            ranges.append(foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = content.length - searchRange.location
        }
        
        let highlightColor = NSColor.yellow.withAlphaComponent(0.4)
        let currentColor = NSColor.orange.withAlphaComponent(0.6)
        
        for (index, range) in ranges.enumerated() {
            let color = index == currentMatchIndex ? currentColor : highlightColor
            textStorage.addAttribute(.backgroundColor, value: color, range: range)
        }
        
        DispatchQueue.main.async {
            if matchCount != ranges.count {
                matchCount = ranges.count
                if currentMatchIndex >= ranges.count {
                    currentMatchIndex = max(0, ranges.count - 1)
                }
            }
        }
        
        if !ranges.isEmpty && currentMatchIndex < ranges.count {
            textView.scrollRangeToVisible(ranges[currentMatchIndex])
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextEditor
        
        init(_ parent: HighlightingTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

#Preview {
    ContentView(document: .constant(LilDocDocument(text: "Hello, world!\nThis is a test.\nHello again!")))
}
