# LilDoc Codebase Walkthrough

*2026-03-02T01:39:29Z by Showboat 0.6.0*
<!-- showboat-id: aee99548-2706-4e53-89d2-cdd6c59e7e5a -->

LilDoc is a minimal, document-based plain text editor for macOS, built with SwiftUI and AppKit. Its defining idea: search isn't a feature you open — it's always present at the bottom of every document window. Beyond that, it's a proper macOS citizen with services, Writing Tools, and standard keyboard shortcuts.

The entire app is just three Swift files. This walkthrough traces through them in the order the system encounters them: app entry point → document model → view layer.

## Project Structure

The source lives entirely in the `LilDoc/` directory. There are no packages, no dependencies, no build plugins — just three Swift files, an asset catalog, and an Info.plist.

```bash
find LilDoc -not -path '*/.*' -not -name '.DS_Store' | sort | sed 's|[^/]*/|  |g'
```

```output
LilDoc
  Assets.xcassets
    AccentColor.colorset
      Contents.json
    AppIcon.appiconset
      Contents.json
      icon-onestroke-v2.png
      icon-onestroke-v3.png
      icon-onestroke-v4.png
      icon-onestroke-v5.png
      icon-onestroke-v6.png
      icon-onestroke.png
      icon.png
    Contents.json
  ContentView.swift
  Info.plist
  LilDocApp.swift
  LilDocDocument.swift
```

The three Swift files map cleanly to the three layers of a SwiftUI document app:

| File | Role |
|------|------|
| `LilDocApp.swift` | App entry point, scene and menu configuration |
| `LilDocDocument.swift` | Document model — reading, writing, and representing plain text |
| `ContentView.swift` | The editor UI — an AppKit `NSTextView` wrapped for SwiftUI, plus a word count overlay |

Let's walk through each one.

## 1. The App Entry Point — `LilDocApp.swift`

The `@main` struct is where macOS learns what kind of app this is. The key decision here is `DocumentGroup` — this single line opts into the entire macOS document architecture: open/save panels, recent documents, window management, and the title bar filename.

```bash
sed -n '11,16p' LilDoc/LilDocApp.swift
```

```output
@main
struct LilDocApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LilDocDocument()) { file in
            ContentView(document: file.$document)
        }
```

`DocumentGroup` creates a scene where each window owns a `LilDocDocument`. When the user opens a file, SwiftUI deserializes it into a `LilDocDocument`, then passes a `Binding<LilDocDocument>` down to `ContentView` via `file.$document`. This binding is the two-way bridge: edits in the view update the document, and the document is what gets serialized back to disk on save.

The default window size is set to 680×420 — compact and focused, matching the "little" in the name.

### Find Menu Commands

The second half of the app struct adds Find menu items. This is where it gets interesting — SwiftUI has no built-in find-and-replace API, so the app bridges directly to AppKit's `NSTextFinder` system:

```bash
sed -n '40,48p' LilDoc/LilDocApp.swift
```

```output
    private func sendFind(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(
            #selector(NSTextView.performFindPanelAction(_:)),
            to: nil,
            from: item
        )
    }
```

This `sendFind` helper is a clever AppKit trick. It creates an `NSMenuItem` with a tag matching the desired `NSTextFinder.Action` (like `.showFindInterface` or `.nextMatch`), then uses the responder chain (`NSApp.sendAction(..., to: nil, ...)`) to route it to whatever `NSTextView` is currently focused. The `to: nil` is the key — it means "send this to the first responder," which will be the text view in the active document window.

This gives LilDoc standard Cmd+F, Cmd+G, Cmd+Shift+G, and Cmd+E shortcuts that work exactly like every other Mac app.

## 2. The Document Model — `LilDocDocument.swift`

The document model is as simple as it gets. The entire model is a single `String`:

```bash
sed -n '11,17p' LilDoc/LilDocDocument.swift
```

```output
struct LilDocDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

```

The `FileDocument` protocol requires two things: reading from disk and writing to disk.

**Reading** decodes UTF-8 data from the file wrapper, throwing a corruption error if the data is missing or not valid UTF-8:

```bash
sed -n '20,27p' LilDoc/LilDocDocument.swift
```

```output
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
```

**Writing** is the inverse — encode the string as UTF-8 and wrap it in a `FileWrapper`:

```bash
sed -n '29,32p' LilDoc/LilDocDocument.swift
```

```output
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
```

The `readableContentTypes` is set to `[.plainText]`, which tells macOS this app handles `public.plain-text` files. This is mirrored in `Info.plist` where `CFBundleDocumentTypes` declares the app as an Editor for `public.plain-text`, which enables "Open With" in Finder and file association.

```bash
cat LilDoc/Info.plist
```

```output
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.plain-text</string>
			</array>
			<key>NSUbiquitousDocumentUserActivityType</key>
			<string>$(PRODUCT_BUNDLE_IDENTIFIER).plaintextdocument</string>
		</dict>
	</array>
</dict>
</plist>
```

## 3. The View Layer — `ContentView.swift`

This is where most of the code lives. The file contains three things:

1. **`ContentView`** — the top-level SwiftUI view
2. **`PlainTextEditor`** — an `NSViewRepresentable` wrapping `NSTextView`
3. **`Coordinator`** — the delegate that bridges AppKit callbacks back to SwiftUI

### ContentView: Layout and Word Count

```bash
sed -n '11,16p' LilDoc/ContentView.swift
```

```output
struct ContentView: View {
    @Binding var document: LilDocDocument
    @SceneStorage("cursorLocation") private var cursorLocation: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

```

Three pieces of state drive the view:

- **`@Binding var document`** — the two-way link to the `LilDocDocument` that the `DocumentGroup` provides. Edits flow up through this binding to trigger saves.
- **`@SceneStorage("cursorLocation")`** — persists the cursor position across app launches. This is a small but thoughtful detail: reopen a document and you're right where you left off.
- **`@Environment(\.colorScheme)`** — drives dark/light mode appearance all the way down into the AppKit text view.

The `wordCount` computed property does a simple whitespace split, filtering empties:

```bash
sed -n '17,23p' LilDoc/ContentView.swift
```

```output
    private var wordCount: Int {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
```

The body is a `ZStack` — the text editor fills the frame, and a word count label floats in the bottom-right corner. When text is selected, it switches from showing word count to showing the selection length in characters:

```bash
sed -n '27,56p' LilDoc/ContentView.swift
```

```output
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
```

The word count label uses `.monospacedDigit()` so the numbers don't jiggle as they change width, and `.foregroundStyle(.tertiary)` to keep it subtle — present but not distracting.

### PlainTextEditor: Bridging to AppKit

SwiftUI's built-in `TextEditor` is too limited for a serious text editor — no find bar, no incremental search, limited control over appearance. So LilDoc wraps `NSTextView` directly using `NSViewRepresentable`.

This is the heart of the app. Let's look at how the text view is created:

```bash
sed -n '65,91p' LilDoc/ContentView.swift
```

```output
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
```

Key setup decisions:

- **`isRichText = false`** — enforces plain text only, no formatting
- **`allowsUndo = true`** — gives us Cmd+Z for free via `NSUndoManager`
- **Smart quotes and dashes disabled** — essential for a plain text editor; you want what you type
- **`usesFindBar = true`** and **`isIncrementalSearchingEnabled = true`** — this is the core feature. The find bar is the thin search strip that appears at the bottom of the text view, and incremental search highlights matches as you type. This is what makes search feel "always present"
- **`drawsBackground = false`** on both scroll view and text view — lets the SwiftUI `.background()` color show through, enabling dark mode support
- **`makeFirstResponder`** — ensures the text view is focused immediately when the window opens, so you can start typing right away

### Keeping SwiftUI and AppKit in Sync

The `updateNSView` method handles the tricky part — synchronizing SwiftUI state changes back into the AppKit text view:

```bash
sed -n '93,110p' LilDoc/ContentView.swift
```

```output
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
```

This method runs whenever SwiftUI's state changes. It only updates the text view's string when it actually differs (avoiding unnecessary resets that would lose the cursor position). On the first update where text matches, it restores the saved cursor position from `@SceneStorage` — but only once (`hasRestoredCursor` flag), so subsequent edits don't fight with the user.

The `min(cursorLocation, textLength)` guard prevents a crash if the file was truncated since the last session.

### Visual Appearance

The `configureAppearance` method sets up the typography and colors. It's called from both `makeNSView` (initial setup) and `updateNSView` (when color scheme changes):

```bash
sed -n '112,154p' LilDoc/ContentView.swift
```

```output
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
```

Design choices embedded in this method:

- **14pt monospaced system font** with **1.6× line height** — comfortable reading density, like a well-set code editor
- **Soft contrast** — not pure black on white. Dark mode uses 90% white text on a dark background; light mode uses 15% black. This reduces eye strain
- **Custom selection color** — subtle gray tones rather than the default blue highlight
- **Generous insets** — 48pt horizontal, 32pt vertical padding inside the text container gives the text room to breathe
- **`widthTracksTextView`** — text wraps to the window width rather than scrolling horizontally
- **Color scheme tracking** — when the user switches between light and dark mode, `lastColorScheme` on the coordinator detects the change and reapplies attributes to the entire text storage. Without this, existing text would keep the old colors

### The Coordinator: Delegate Bridge

```bash
sed -n '160,184p' LilDoc/ContentView.swift
```

```output
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
```

The Coordinator is the standard `NSViewRepresentable` pattern for receiving AppKit delegate callbacks. It does two things:

1. **`textDidChange`** — when the user types, it pushes the new text back up to the SwiftUI binding (`parent.text`), which updates the `LilDocDocument`, which marks the document as dirty for saving.

2. **`textViewDidChangeSelection`** — tracks cursor position and selection length. The cursor position flows to `@SceneStorage` for persistence. The selection length drives the word count / selection count toggle in the overlay.

Both methods guard against redundant updates (checking if the value actually changed before writing), which prevents SwiftUI update cycles.

## How It All Connects

The data flow forms a clean loop:

1. **File → Document**: macOS calls `LilDocDocument.init(configuration:)` to load a file
2. **Document → View**: `DocumentGroup` passes `$document` as a binding to `ContentView`
3. **View → AppKit**: `ContentView` passes `$document.text` into `PlainTextEditor`, which sets it on `NSTextView`
4. **AppKit → View**: User types → `Coordinator.textDidChange` → updates `parent.text` binding
5. **View → Document**: The binding propagates back up to `LilDocDocument.text`
6. **Document → File**: SwiftUI detects the mutation and auto-saves via `fileWrapper(configuration:)`

The find bar lives entirely in AppKit's `NSTextFinder`, activated by the menu commands in `LilDocApp`. It searches and highlights within `NSTextView` directly — no custom search logic needed.

## Summary

LilDoc is a study in restraint. Three files, no dependencies, ~190 lines of Swift. It gets a lot for free by leaning on platform frameworks:

- **Document management** from `DocumentGroup` and `FileDocument`
- **Find and replace** from `NSTextFinder`
- **Undo/redo** from `NSUndoManager`
- **Services and Writing Tools** from being a proper `NSTextView`
- **Dark mode** from reading SwiftUI's `colorScheme` environment

The one piece of real engineering is the `NSViewRepresentable` bridge — getting AppKit's `NSTextView` to play nicely inside SwiftUI's state management system while preserving cursor position across launches. That's the code worth studying if you're building a similar hybrid app.
