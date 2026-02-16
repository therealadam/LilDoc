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
    @Binding var replaceText: String
    @Binding var isReplaceVisible: Bool
    var currentMatchIndex: Int
    var matchCount: Int
    @FocusState.Binding var isSearchFocused: Bool
    var jumpBackDisabled: Bool
    var onDismiss: () -> Void
    var onSubmit: () -> Void
    var onJumpBack: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: { isReplaceVisible.toggle() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isReplaceVisible ? 90 : 0))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isReplaceVisible ? "Hide replace" : "Show replace")

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

                if !searchText.isEmpty {
                    if matchCount > 0 {
                        Text("\(currentMatchIndex + 1)/\(matchCount)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No matches")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red.opacity(0.8))
                    }
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

            if isReplaceVisible {
                HStack(spacing: 8) {
                    // Spacer to align with search field (matches disclosure chevron width)
                    Color.clear.frame(width: 9, height: 1)

                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.plain)
                        .frame(width: 120)

                    Button(action: onReplace) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty || matchCount == 0)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Replace")

                    Button(action: onReplaceAll) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 11))
                            .overlay(alignment: .topTrailing) {
                                Text("all")
                                    .font(.system(size: 7, weight: .semibold))
                                    .offset(x: 10, y: -4)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty || matchCount == 0)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Replace all")
                }
            }
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
    @State private var replaceText = ""
    @State private var isReplaceVisible = false
    @State private var currentMatchIndex = 0
    @State private var matchCount = 0
    @State private var matchRanges: [NSRange] = []
    @State private var selectionLength: Int = 0
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var editorFocusTrigger = 0
    @State private var jumpBackPosition: Int? = nil
    @State private var jumpBackTrigger = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    private var wordCount: Int {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var body: some View {
        ZStack {
            HighlightingTextEditor(
                text: $document.text,
                searchText: isSearchExpanded ? searchText : "",
                currentMatchIndex: $currentMatchIndex,
                matchCount: $matchCount,
                matchRanges: $matchRanges,
                focusTrigger: editorFocusTrigger,
                colorScheme: colorScheme,
                cursorLocation: $cursorLocation,
                selectionLength: $selectionLength,
                jumpBackTrigger: jumpBackTrigger,
                jumpBackPosition: jumpBackPosition
            )
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))

            VStack {
                HStack {
                    Spacer()
                    if isSearchExpanded {
                        SearchOverlay(
                            searchText: $searchText,
                            replaceText: $replaceText,
                            isReplaceVisible: $isReplaceVisible,
                            currentMatchIndex: currentMatchIndex,
                            matchCount: matchCount,
                            isSearchFocused: $isSearchFocused,
                            jumpBackDisabled: jumpBackPosition == nil,
                            onDismiss: dismissSearch,
                            onSubmit: { editorFocusTrigger += 1 },
                            onJumpBack: jumpBack,
                            onPrevious: previousMatch,
                            onNext: nextMatch,
                            onReplace: replaceCurrent,
                            onReplaceAll: replaceAll
                        )
                    }
                }
                .padding([.top, .trailing], 16)

                Spacer()

                HStack {
                    Spacer()
                    Group {
                        if selectionLength > 0 {
                            Text("\(selectionLength) characters selected")
                        } else {
                            Text("\(wordCount) words")
                        }
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            guard controlActiveState == .key else { return }
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

    private func replaceCurrent() {
        guard currentMatchIndex < matchRanges.count else { return }
        let range = matchRanges[currentMatchIndex]
        let nsText = document.text as NSString
        guard range.location + range.length <= nsText.length else { return }
        document.text = nsText.replacingCharacters(in: range, with: replaceText)
    }

    private func replaceAll() {
        guard !matchRanges.isEmpty else { return }
        var result = document.text as NSString
        // Replace in reverse order to preserve earlier indices
        for range in matchRanges.reversed() {
            guard range.location + range.length <= result.length else { continue }
            result = result.replacingCharacters(in: range, with: replaceText) as NSString
        }
        document.text = result as String
    }
}

struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var searchText: String
    @Binding var currentMatchIndex: Int
    @Binding var matchCount: Int
    @Binding var matchRanges: [NSRange]
    var focusTrigger: Int
    var colorScheme: ColorScheme
    @Binding var cursorLocation: Int
    @Binding var selectionLength: Int
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

        let textChanged = textView.string != text
        if textChanged {
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

        let searchChanged = context.coordinator.lastSearchText != searchText
        let matchIndexChanged = context.coordinator.lastMatchIndex != currentMatchIndex
        if textChanged || searchChanged || matchIndexChanged {
            context.coordinator.lastSearchText = searchText
            applyHighlighting(to: textView, context: context)
        }
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
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
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
        
        // Clamp match index to valid range before using it
        let effectiveIndex: Int
        if ranges.isEmpty {
            effectiveIndex = 0
        } else if currentMatchIndex >= ranges.count {
            effectiveIndex = max(0, ranges.count - 1)
        } else {
            effectiveIndex = currentMatchIndex
        }

        for (index, range) in ranges.enumerated() {
            let color = index == effectiveIndex ? currentColor : highlightColor
            textStorage.addAttribute(.backgroundColor, value: color, range: range)
        }

        DispatchQueue.main.async {
            matchCount = ranges.count
            matchRanges = ranges
            currentMatchIndex = effectiveIndex
        }

        if !ranges.isEmpty {
            let range = ranges[effectiveIndex]
            if context.coordinator.lastMatchIndex != effectiveIndex {
                context.coordinator.lastMatchIndex = effectiveIndex
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
        var lastSearchText: String = ""
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
            let range = textView.selectedRange()
            if range.location != parent.cursorLocation {
                parent.cursorLocation = range.location
            }
            if range.length != parent.selectionLength {
                parent.selectionLength = range.length
            }
        }
    }
}



#Preview {
    ContentView(document: .constant(LilDocDocument(text: "Hello, world!\nThis is a test.\nHello again!")))
}
