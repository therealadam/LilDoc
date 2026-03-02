# Lil' Doc Design Brief

## What it is

A plain text editor for macOS where search is the foundation, not a feature. You open a document, you search through your words, you navigate by finding. Everything else stays out of the way.

## Visual direction

Quiet, native, typographic. The editor should feel like a sheet of paper with just enough chrome to orient you. No panels, no toolbars, no tabs. The window is the document.

## Color

- **Light mode:** Near-white background (`#fafafa` / `0.98`), dark text. Search highlights in warm yellow tones — dimmer for all matches, brighter for the current match.
- **Dark mode:** Near-black background (`#1f1f1f` / `0.12`), light text. Search highlights shift to amber/gold. Same dim/bright distinction for all vs. current match.
- Accent color should be warm and unobtrusive. Avoid cool blues — the app should feel like paper and ink, not a code editor.
- Status text and secondary UI use tertiary foreground color — visible but never competing with the document.

## Typography

- **Editor:** Monospace system font, 14pt, 1.6x line height. Generous but not wasteful.
- **Status bar:** 11pt monospaced digits. Quiet.
- **Overlays (search, agent field):** 12pt monospace. Consistent with the editor's voice.
- The app speaks in one typeface family. No sans-serif labels mixed with monospace content.

## Layout

- **Single-window, document-based.** Each file gets its own window. No multi-document chrome.
- **Editor fills the window.** Content insets provide breathing room at the edges.
- **Status bar:** Bottom-right corner. Shows word count normally, character selection count when text is selected.
- **Search overlay:** Floating pill with material blur background. Contains the search field, match counter ("3/15"), previous/next buttons, jump-back button, close button.
- **Agent field (planned):** Bottom-left corner, toggled with a keyboard shortcut. Same material blur treatment as search. Max width ~400px. Agent responses appear as a fading overlay near the top.

## Interaction

- **Search is always close.** Cmd+/ opens the search field. Typing a query immediately highlights all word-boundary matches in the document. The current match scrolls into view.
- **Navigation is spatial.** Next match (Cmd+G), previous match (Cmd+Shift+G). The editor remembers where your cursor was before you jumped — "jump back" returns you there. Peek at a match, then go back to writing.
- **Native macOS behavior.** System Find bar via Cmd+F. Writing Tools, Services menu, standard text selection, drag-and-drop. The app should never feel like it's fighting the platform.
- **State persists.** Search text and cursor position survive across app launches via SceneStorage. Reopening a document puts you back where you left off.
- **Undo covers everything.** Agent edits, manual typing, and search-triggered navigation all go through the NSTextView undo manager. Cmd+Z always works.

## Principles

1. **The document is the interface.** Every pixel that isn't the document needs to justify its existence.
2. **Warmth over precision.** Amber highlights, paper-like backgrounds, generous line height. The app should feel inviting, not clinical.
3. **No modes.** Search, editing, and agent interaction coexist. You don't "enter search mode" — you just start searching while you're editing.
4. **Platform native.** Use system materials, system fonts, system shortcuts. If macOS already does something well, use it.
5. **Progressive disclosure.** Word count is always visible. Search appears when summoned. Agent field appears when summoned and only on supported hardware. Nothing demands attention uninvited.

## Constraints

- Zero external dependencies. System frameworks only.
- ~420 lines of Swift across three source files. Complexity is the enemy.
- macOS only. No iOS, no Catalyst.
- Agent features require Apple Silicon and macOS 26+. They must degrade gracefully — the app works without them.
