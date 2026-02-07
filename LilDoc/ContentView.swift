//
//  ContentView.swift
//  LilDoc
//
//  Created by Adam Keys on 1/31/26.
//

import SwiftUI
import AppKit

struct SearchOverlay: View {
    @Binding var searchText: String
    var currentMatchIndex: Int
    var matchCount: Int
    @FocusState.Binding var isSearchFocused: Bool
    var jumpBackDisabled: Bool
    var onDismiss: () -> Void
    var onSubmit: () -> Void
    var onJumpBack: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .trailing) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 120)
                    .focused($isSearchFocused)
                    .onSubmit(onSubmit)
                    .onExitCommand(perform: onDismiss)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if !searchText.isEmpty && matchCount > 0 {
                Text("\(currentMatchIndex + 1)/\(matchCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 4) {
                Button(action: onJumpBack) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(jumpBackDisabled)
                .accessibilityLabel("Jump back")
                
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(searchText.isEmpty || matchCount == 0)
                .accessibilityLabel("Previous match")
                
                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("g", modifiers: .command)
                .disabled(searchText.isEmpty || matchCount == 0)
                .accessibilityLabel("Next match")
            }
            .foregroundStyle(.secondary)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}

struct ContentView: View {
    @Binding var document: LilDocDocument
    @SceneStorage("searchText") private var searchText = ""
    @SceneStorage("cursorLocation") private var cursorLocation: Int = 0
    @State private var currentMatchIndex = 0
    @State private var matchCount = 0
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var editorFocusTrigger = 0
    @State private var jumpBackPosition: Int? = nil
    @State private var jumpBackTrigger = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HighlightingTextEditor(
                text: $document.text,
                searchText: searchText,
                currentMatchIndex: $currentMatchIndex,
                matchCount: $matchCount,
                focusTrigger: editorFocusTrigger,
                colorScheme: colorScheme,
                cursorLocation: $cursorLocation,
                jumpBackTrigger: jumpBackTrigger,
                jumpBackPosition: jumpBackPosition
            )
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
            
            if isSearchExpanded {
                SearchOverlay(
                    searchText: $searchText,
                    currentMatchIndex: currentMatchIndex,
                    matchCount: matchCount,
                    isSearchFocused: $isSearchFocused,
                    jumpBackDisabled: jumpBackPosition == nil,
                    onDismiss: dismissSearch,
                    onSubmit: { editorFocusTrigger += 1 },
                    onJumpBack: jumpBack,
                    onPrevious: previousMatch,
                    onNext: nextMatch
                )
                .padding([.top, .trailing], 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            expandSearch()
        }
    }
    
    private func dismissSearch() {
        isSearchFocused = false
        isSearchExpanded = false
        editorFocusTrigger += 1
    }
    
    private func previousMatch() {
        if matchCount > 0 {
            jumpBackPosition = cursorLocation
            currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        }
    }
    
    private func nextMatch() {
        if matchCount > 0 {
            jumpBackPosition = cursorLocation
            currentMatchIndex = (currentMatchIndex + 1) % matchCount
        }
    }
    
    private func jumpBack() {
        guard let position = jumpBackPosition else { return }
        jumpBackPosition = nil
        jumpBackTrigger += 1
        cursorLocation = position
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
    @Binding var cursorLocation: Int
    var jumpBackTrigger: Int
    var jumpBackPosition: Int?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator
        
        // Enable standard macOS Find bar (Cmd+F)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        
        configureAppearance(textView, context: context)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        
        configureAppearance(textView, context: context)
        
        if textView.string != text {
            textView.string = text
            
            if !context.coordinator.hasRestoredCursor && cursorLocation > 0 {
                context.coordinator.hasRestoredCursor = true
                let textLength = (textView.string as NSString).length
                let safeLocation = min(cursorLocation, textLength)
                textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
                textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
            }
        }
        
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        
        if jumpBackTrigger != context.coordinator.lastJumpBackTrigger {
            context.coordinator.lastJumpBackTrigger = jumpBackTrigger
            if let position = jumpBackPosition {
                let textLength = (textView.string as NSString).length
                let safeLocation = min(position, textLength)
                textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
                textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
            }
        }
        
        applyHighlighting(to: textView, context: context)
    }
    
    private func configureAppearance(_ textView: NSTextView, context: Context) {
        let isDark = colorScheme == .dark
        
        let fontSize: CGFloat = 14
        let lineHeight: CGFloat = 1.6
        
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeight
        
        let textColor = isDark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        
        let typingAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor
        ]
        
        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = typingAttributes
        textView.textColor = textColor
        textView.insertionPointColor = isDark ? .white : .black
        textView.selectedTextAttributes = [
            .backgroundColor: isDark 
                ? NSColor(white: 0.35, alpha: 1) 
                : NSColor(white: 0.8, alpha: 1)
        ]
        
        if let textStorage = textView.textStorage, textStorage.length > 0,
           context.coordinator.lastColorScheme != colorScheme {
            context.coordinator.lastColorScheme = colorScheme
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttributes(typingAttributes, range: fullRange)
        }
        
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
            
            // Word-boundary check: only match if not surrounded by alphanumerics
            let isWordBoundary: Bool = {
                let beforeOK: Bool
                if foundRange.location == 0 {
                    beforeOK = true
                } else {
                    let charBefore = content.character(at: foundRange.location - 1)
                    if let scalar = Unicode.Scalar(charBefore) {
                        beforeOK = !CharacterSet.alphanumerics.contains(scalar)
                    } else {
                        beforeOK = true // Surrogate pair, treat as boundary
                    }
                }
                
                let afterOK: Bool
                let afterIndex = foundRange.location + foundRange.length
                if afterIndex >= content.length {
                    afterOK = true
                } else {
                    let charAfter = content.character(at: afterIndex)
                    if let scalar = Unicode.Scalar(charAfter) {
                        afterOK = !CharacterSet.alphanumerics.contains(scalar)
                    } else {
                        afterOK = true // Surrogate pair, treat as boundary
                    }
                }
                
                return beforeOK && afterOK
            }()
            
            if isWordBoundary {
                ranges.append(foundRange)
            }
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
        var lastColorScheme: ColorScheme?
        var hasRestoredCursor = false
        var lastJumpBackTrigger: Int = 0
        
        init(_ parent: HighlightingTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let location = textView.selectedRange().location
            if location != parent.cursorLocation {
                parent.cursorLocation = location
            }
        }
    }
}



#Preview {
    ContentView(document: .constant(LilDocDocument(text: "Hello, world!\nThis is a test.\nHello again!")))
}
