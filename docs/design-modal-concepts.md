# Search Overlay Modal — Design Concepts

Five directions for a modal overlay that lets the user define up to 4 search strings, each color-coded and highlighted in the document with match counts.

All concepts use the same color palette for the 4 search slots:
- Amber `#D4943A`
- Coral `#C15B54`
- Sage `#5E9A5B`
- Lavender `#7B6DAF`

Typography is SF Mono for search terms, SF Pro for labels and hints.

---

## A — Spotlight Stack

Centered floating modal, summoned and dismissed with a keystroke. Four search rows stacked vertically. Each row has a colored dot on the left, the search term in monospace in the middle, and a match count ("3 matches") on the right. The active/focused row gets a subtle gray background. Keyboard hints along the bottom: "Tab to switch rows · Return to navigate · Esc to close."

Feels like a command palette. You summon it, type your terms, dismiss it. The document is dimmed behind it.

**Strengths:** Familiar Spotlight/Raycast interaction pattern. Compact. Gets out of the way when dismissed.
**Weaknesses:** You can't see search results and the overlay simultaneously. Requires opening/closing to adjust terms.

---

## B — Color Bar Panel

Centered floating modal with thick colored left borders on each row (4px, one per search color). Match counts are right-aligned and rendered in the matching color. Rows with active search terms get a faint color-tinted background. Empty rows show a dash placeholder.

More structural and editorial than A. The color bars create a strong vertical lane that immediately maps each row to its highlight color in the document.

**Strengths:** Strong color identity. The left-border treatment scales well visually. Counts in matching colors reinforce the mapping.
**Weaknesses:** Similar modal tradeoffs to A — still a floating panel you open and close.

---

## C — Bottom Tray

Anchored to the bottom edge of the window, like a toolbar that slides up. Four horizontal chips sit side by side, each tinted with its search color. Active chips show the search term and count. Empty slots show a dashed "+" affordance inviting a new search. Keyboard hints below: "Cmd+1–4 to focus · Arrows to navigate matches · Esc to close."

The document text stays fully visible above. This is the least modal option.

**Strengths:** Non-modal — could stay visible while editing. Compact horizontal layout preserves vertical space. The "+" empty slot is a clear affordance. Direct keyboard access via Cmd+1–4.
**Weaknesses:** Horizontal space gets tight with longer search terms. Less room for detail per search. Eats into the bottom of the window where the word count status bar currently lives.

---

## D — Minimal Index Cards *(not yet implemented in Paper)*

A centered overlay with 4 small cards in a 2x2 grid. Each card uses its search color as a very light full-background tint. The search term is large and bold in the center. The match count is a large number in the top-right corner. Empty cards show a faint "+" in the center.

More playful and visual — you see your 4 searches as a small dashboard at a glance.

**Strengths:** Scannable at a glance. The 2x2 layout gives each search more visual weight. Good when search terms are short.
**Weaknesses:** Takes up more screen space than a list. The grid layout may feel heavy for only 1–2 active searches. Longer search terms could overflow the card width.

---

## E — Sidebar Ledger *(not yet implemented in Paper)*

A narrow panel (~200px) that slides in from the right edge of the window. Each search gets a full row with a color swatch, the search term, the match count, and small previous/next navigation arrows. The document text reflows to accommodate it.

The most persistent option — you'd leave it open while editing, like a reference panel.

**Strengths:** Always visible alongside the document. Room for per-search navigation controls. Could expand later to show match previews or line numbers.
**Weaknesses:** The biggest departure from the "window is the document" philosophy. Reflows the editor text, which could be jarring. Heavier UI footprint than any other option.
