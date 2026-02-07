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
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var editorFocusTrigger = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HighlightingTextEditor(
            text: $document.text,
            searchText: searchText,
            currentMatchIndex: $currentMatchIndex,
            matchCount: $matchCount,
            focusTrigger: editorFocusTrigger,
            colorScheme: colorScheme
        )
        .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    if isSearchExpanded || !searchText.isEmpty {
                        ZStack(alignment: .trailing) {
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .focused($isSearchFocused)
                                .onSubmit {
                                    editorFocusTrigger += 1
                                }
                                .onExitCommand {
                                    isSearchFocused = false
                                    if searchText.isEmpty { isSearchExpanded = false }
                                    editorFocusTrigger += 1
                                }
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 4)
                            }
                        }
                        
                        if !searchText.isEmpty && matchCount > 0 {
                            Text("\(currentMatchIndex + 1)/\(matchCount)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(action: previousMatch) {
                            Image(systemName: "chevron.up")
                        }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                        .disabled(searchText.isEmpty || matchCount == 0)
                        
                        Button(action: nextMatch) {
                            Image(systemName: "chevron.down")
                        }
                        .keyboardShortcut("g", modifiers: .command)
                        .disabled(searchText.isEmpty || matchCount == 0)
                    } else {
                        Button(action: { expandSearch() }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            expandSearch()
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && searchText.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !isSearchFocused && searchText.isEmpty {
                        isSearchExpanded = false
                    }
                }
            }
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
    
    private func expandSearch() {
        isSearchExpanded = true
        isSearchFocused = true
    }
}

struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var searchText: String
    @Binding var currentMatchIndex: Int
    @Binding var matchCount: Int
    var focusTrigger: Int
    var colorScheme: ColorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        
        configureAppearance(textView)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        
        configureAppearance(textView)
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        
        applyHighlighting(to: textView, context: context)
    }
    
    private func configureAppearance(_ textView: NSTextView) {
        let isDark = colorScheme == .dark
        
        let fontSize: CGFloat = 14
        let lineHeight: CGFloat = 1.6
        
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeight
        
        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.textColor = isDark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        textView.insertionPointColor = isDark ? .white : .black
        textView.selectedTextAttributes = [
            .backgroundColor: isDark 
                ? NSColor(white: 0.35, alpha: 1) 
                : NSColor(white: 0.8, alpha: 1)
        ]
        
        textView.textContainerInset = NSSize(width: 48, height: 32)
        
        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        }
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
        
        let isDark = colorScheme == .dark
        let highlightColor = isDark 
            ? NSColor(red: 0.6, green: 0.5, blue: 0.2, alpha: 0.5)
            : NSColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 0.6)
        let currentColor = isDark
            ? NSColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 0.7)
            : NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.8)
        
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
            let range = ranges[currentMatchIndex]
            if context.coordinator.lastMatchIndex != currentMatchIndex {
                context.coordinator.lastMatchIndex = currentMatchIndex
                textView.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
                textView.scrollRangeToVisible(range)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextEditor
        var lastFocusTrigger: Int = 0
        var lastMatchIndex: Int = -1
        
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
