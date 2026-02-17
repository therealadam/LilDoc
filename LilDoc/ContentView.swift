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
    @SceneStorage("cursorLocation") private var cursorLocation: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    private var wordCount: Int {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    @State private var selectionLength: Int = 0

    var body: some View {
        ZStack {
            PlainTextEditor(
                text: $document.text,
                colorScheme: colorScheme,
                cursorLocation: $cursorLocation,
                selectionLength: $selectionLength
            )
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))

            VStack {
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
    }
}

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var colorScheme: ColorScheme
    @Binding var cursorLocation: Int
    @Binding var selectionLength: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator

        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        textView.drawsBackground = false

        configureAppearance(textView, context: context)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var lastColorScheme: ColorScheme?
        var hasRestoredCursor = false

        init(_ parent: PlainTextEditor) {
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
