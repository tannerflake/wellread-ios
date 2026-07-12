# Goodreads Import Redesign — Requirements

Major UX overhaul of the Goodreads import in Spine. Two problems: matching quality is bad, and the flow tries to one-shot the whole import instead of walking the user through it. This doc lists requirements. Implementation details are up to you.

## Goals

- Fix data matching from Goodreads into Spine.
- Replace the one-shot import with a book-by-book wizard integrated into getting-started.
- Let users pick up where they left off.
- Simplify import to a single path: download CSV from Goodreads, upload CSV.

## 1. Matching quality

- Matching is currently missing ~60% of books and pulling in junk (wrong/non-matching books).
- ISBN should be the primary identifier for matching. Every book has an ISBN key; use it. Investigate why current matching fails despite ISBN being available (likely falling back to title matching).
- Do not surface books that don't confidently match.

## 2. Import wizard (read books)

Replace the one-shot import with a step-by-step wizard.

- Goes book by book, one at a time, showing the matched book fast.
- Each book shows:
  - Cover
  - The user's Goodreads star rating
  - Tier options as buttons below the star rating, defaulting to **Unranked**. User can optionally drop the book into a tier right here without drag-and-drop, but is not required to.
  - The user's Goodreads text review below that.
- User cannot edit content from the main screen. Three actions: **Looks good**, **Edit**, **Skip**.
- Progress indicator showing how many books imported and how many remain.
- Order: start with most recently read books first.
- Only imports **read** books in this phase. Ignore want-to-read / queue and anything else pulled from the CSV.
- Include an **Import all** option, but visually indicate the wizard is the recommended path.

## 3. Resume / save progress

- Wizard saves the user's place. If they close out, their position is held.
- They can jump back in and continue where they left off, and this should be obvious to them.
- If they exit early and land on their tier list, show a callout reminder pointing them to finish importing. Tapping it takes them straight back to where they left off in the flow.

## 4. Queue books (after read books)

- Only after all read books are handled, prompt: "Do you want to add the books in your queue (not yet read)?"
- Give two options: import automatically, or import one by one.

## 5. CSV-only entry path

- Remove / hide the paste-your-file workaround entirely. Do not use it.
- Single supported path: user goes to Goodreads, downloads their CSV, and uploads the CSV.
- The upload step should point users to the right place in their files. This already works well; keep it.

## Out of scope

- Want-to-read and other non-read lists during the read-books phase (handled only in the queue step).
- The old paste-in flow.