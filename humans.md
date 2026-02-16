# Humans Guide to Lil' Doc

Lil' Doc is a minimal, search-focused plain text editor for macOS. Search isn't a feature bolted onto an editor -- it's the foundational interaction. You open a document, you search through your words, you navigate by finding.

The entire app is about 420 lines of Swift across three source files. There are zero external dependencies.

## Project layout

```
LilDoc/
  LilDocApp.swift          # App entry point, menu commands, window config
  LilDocDocument.swift     # Document model (reading/writing plain text)
  ContentView.swift        # All UI: editor, search overlay, text highlighting
  Info.plist               # Bundle configuration
  Assets.xcassets/         # App icon and accent color
LilDoc.xcodeproj/          # Xcode project and build settings
mise.toml                  # Build tasks (setup, app, install)
conductor.json             # Agent tooling config
```

## Domain model

There are three concepts worth knowing:

**Document** (`LilDocDocument`): A wrapper around a plain text string. Implements SwiftUI's `FileDocument` protocol so the system handles open, save, and autosave. Reads and writes UTF-8. That's it -- there's no rich text, no format metadata, just a `String`.

**Search**: The core interaction. Searching means finding word-boundary matches in the document text. A match must be bordered by non-alphanumeric characters (spaces, punctuation, start/end of text). Searching for "the" won't highlight "there". Matches are case-insensitive. The search state tracks the query text, all match ranges, and which match is "current."

**Jump back**: When you navigate between matches (next/previous), the editor remembers where your cursor was before the jump. The "jump back" action returns you to that position. This lets you peek at a match and then return to where you were writing.

## Architecture

The app follows the standard SwiftUI document-based app pattern with one important bridge into AppKit.

### Scene setup (LilDocApp.swift)

`LilDocApp` is the `@main` entry point. It creates a `DocumentGroup` scene that produces a `ContentView` for each open document. It also registers the Cmd+/ keyboard shortcut for search, which posts a `Notification` rather than calling into the view directly. This decoupling lets the menu command work regardless of view focus state.

### View layer (ContentView.swift)

Three structs handle all the UI:

**`ContentView`** is the root view for each document window. It owns the search state (`searchText`, `currentMatchIndex`, `matchCount`) and coordinates between the editor and the search overlay. Search text and cursor position are persisted across app launches via `@SceneStorage`. ContentView also defines the navigation logic: `nextMatch`, `previousMatch`, `jumpBack`, `expandSearch`, and `dismissSearch`.

**`SearchOverlay`** is a pure presentation component. It renders the search field, match counter ("3/15"), navigation buttons (previous, next, jump back), and a close button. It takes bindings and callbacks from ContentView and has no logic of its own. It appears as a floating pill in the top-right corner with a material blur background.

**`HighlightingTextEditor`** is where most of the complexity lives. It's an `NSViewRepresentable` that wraps an `NSTextView` inside an `NSScrollView`. This bridge from SwiftUI to AppKit is necessary because SwiftUI's `TextEditor` doesn't support attributed text (highlight colors), fine cursor control, or the macOS services menu.

### How highlighting works

The `applyHighlighting` method runs on every view update. It:

1. Strips all existing background color attributes from the text storage
2. Walks through the document text finding case-insensitive matches
3. Checks each match for word boundaries (non-alphanumeric characters on both sides)
4. Applies a dimmer background color to all matches
5. Applies a brighter background color to the current match
6. Scrolls the current match into view and positions the cursor after it

Light and dark mode use different highlight colors (yellow tones in light, amber/gold in dark).

### The Coordinator

`HighlightingTextEditor.Coordinator` is the `NSTextViewDelegate`. It handles two-way sync:

- When the user types, `textDidChange` pushes the new text back to the SwiftUI binding
- When the user moves the cursor, `textViewDidChangeSelection` updates the stored cursor position
- It also tracks state to prevent redundant updates (last focus trigger, last match index, color scheme changes, cursor restoration)

### Data flow

```
User types in editor
  -> Coordinator.textDidChange
    -> updates document.text binding
      -> SwiftUI re-renders
        -> updateNSView called
          -> applyHighlighting runs against current searchText

User presses Cmd+/
  -> Notification posted
    -> ContentView.expandSearch
      -> SearchOverlay appears, search field focused

User types search query
  -> searchText binding updates
    -> SwiftUI re-renders ContentView
      -> HighlightingTextEditor.updateNSView
        -> applyHighlighting finds matches, updates matchCount

User presses Cmd+G (next match)
  -> ContentView.nextMatch
    -> saves cursor to jumpBackPosition
    -> increments currentMatchIndex (wraps around)
      -> applyHighlighting scrolls to new match
```

### State persistence

Two values survive across app launches via `@SceneStorage`:
- `searchText`: The last search query for each document window
- `cursorLocation`: The cursor position, restored when the document reopens

## Making changes

### Build and run

You need macOS with Xcode installed. Then:

```bash
# Build (verify it compiles)
mise run setup

# Build and launch the app
mise run app

# Build release and install to ~/Applications
mise run install
```

Or use `xcodebuild` directly:

```bash
xcodebuild -project LilDoc.xcodeproj -scheme LilDoc -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/LilDoc.app
```

### Where to make changes

**Adding a new document feature** (e.g., word count, format support): Start in `LilDocDocument.swift`. If the feature needs UI, add state to `ContentView` and either extend `SearchOverlay` or create a new overlay view.

**Changing search behavior** (e.g., regex search, substring matching): The search logic lives in `HighlightingTextEditor.applyHighlighting` (ContentView.swift, around line 297). The word-boundary check is the closure starting at line 324. To change what counts as a match, modify this method.

**Changing the editor appearance** (fonts, colors, spacing): Look at `HighlightingTextEditor.configureAppearance` (ContentView.swift, line 253). Font size, line height, text colors, selection colors, and content insets are all set there. Highlight colors for search matches are in `applyHighlighting` around line 360.

**Adding keyboard shortcuts**: Global shortcuts (like Cmd+/) go in `LilDocApp.swift` in the `.commands` modifier. View-local shortcuts (like Cmd+G for next match) go on the relevant button in `SearchOverlay`.

**Changing the search UI**: `SearchOverlay` (ContentView.swift, line 11) is self-contained. Its callbacks (`onDismiss`, `onNext`, etc.) are wired up in `ContentView.body`.

### Things to know

- There are no tests. Verify changes by building and running the app.
- The app uses a monospace system font at 14pt with 1.6x line height. These values are hardcoded in `configureAppearance`.
- `NSTextView` works with `NSRange` and `NSString`, not Swift `String.Index`. Be careful with Unicode when working in `applyHighlighting` or the Coordinator.
- SwiftUI and AppKit have different update cycles. The `DispatchQueue.main.async` calls in `applyHighlighting` exist to avoid mutating SwiftUI state during a view update pass.
- The app is sandboxed with user-selected file access only.
