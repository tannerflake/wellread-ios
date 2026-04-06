My take: for iOS, the best version is not “Goodreads OAuth import.” It is a guided in-app export + auto-capture + preview import flow.

Why: Goodreads’ public developer API is effectively not a path here. Goodreads says it no longer issues new developer keys and planned to retire the existing public developer tools, while their supported bulk path is still the library CSV export flow. Goodreads’ export flow is tied to the Import/Export page, where the user clicks Export Library to generate a CSV. Multiple Goodreads help/forum pages also indicate this export is available on the desktop site, and users often have trouble doing it in the mobile app itself.  ￼

On iOS, Apple gives you a few relevant building blocks:
	•	SFSafariViewController shows a self-contained web interface inside your app
	•	AuthenticationServices is the framework Apple provides for sign-in/auth experiences
	•	WKDownloadDelegate exists specifically to track downloads and handle download events
	•	UIDocumentPickerViewController is the native way to let users pick a file if you need a fallback  ￼

The product truth

You probably cannot fully automate Goodreads export server-side in a clean, durable, policy-safe way.

You do not want:
	•	scraping Goodreads credentials yourself
	•	pretending Goodreads has a real import API when it doesn’t
	•	forcing a fragile background browser automation flow that breaks the second Goodreads tweaks HTML

You do want:
	•	keep the user in your app as much as possible
	•	use Goodreads’ own export step
	•	intercept the downloaded CSV inside your app if possible
	•	give a clean fallback when iOS or Goodreads gets in the way

Best UX option: “In-app guided export”

Ideal flow
	1.	User taps Import from Goodreads
	2.	Show a 2-screen explainer:
	•	“You’ll sign in to Goodreads”
	•	“You’ll generate your library export”
	•	“Spines will capture the CSV and import it automatically”
	3.	Open Goodreads export flow in an in-app browser surface
	4.	User logs in
	5.	User taps Export Library
	6.	When Goodreads generates the CSV link, user taps it
	7.	Your app captures the download
	8.	You parse locally or upload to your backend
	9.	Show import preview:
	•	matched books
	•	unmatched books
	•	duplicates found
	•	shelves/status mapping
	10.	User confirms import

This is the slickest experience that is still grounded in reality.

Which browser surface should you use?

Option A: WKWebView + download interception

This is the highest-upside option for polish.

Why it’s attractive:
	•	fully embedded in your app
	•	you can detect the CSV download
	•	you can keep the user from bouncing into Files/Safari
	•	you can transition directly from download to parse/import

Why it’s risky:
	•	some auth flows behave better in Safari-based surfaces than in raw web views
	•	Goodreads may change page structure or use flows that are annoying in WKWebView
	•	cookie/login weirdness is more common in embedded web views

Use this if:
	•	you have strong iOS engineering
	•	you’re okay testing thoroughly
	•	you’re willing to maintain edge cases

Option B: SFSafariViewController

This is the safer UX/engineering middle ground.

Pros:
	•	closer to real Safari behavior
	•	usually better for login reliability and autofill
	•	still feels in-app enough for most users  ￼

Cons:
	•	download interception/control is weaker than with your own web view
	•	you may not be able to grab the CSV seamlessly
	•	you may end up needing a share sheet or Files fallback

Use this if:
	•	you want fewer auth headaches
	•	you can accept a slightly less magical import

Option C: external Safari + “Open in Spines” fallback

Least elegant, but very robust.

Flow:
	•	launch Goodreads export page in Safari
	•	instruct user to tap export
	•	user downloads CSV
	•	share to Spines or pick file in Spines

This is the fallback, not the primary.

What I would actually build

I’d do this as a 2-path system:

Path 1, primary

Embedded WKWebView importer
	•	open Goodreads sign-in / export page
	•	detect when the generated file is a CSV
	•	capture it directly with WKDownloadDelegate
	•	parse immediately
	•	no Files app step if all goes well

Path 2, fallback

“Already downloaded your CSV?”
	•	native file picker via UIDocumentPickerViewController
	•	or share extension / “Open in Spines”

That gives you the slick path and a recovery path.

That is the right PM move. Trying to force one perfect flow only will burn time on edge cases.

Important constraint you should design around

Goodreads export appears to be a generated file, not always an immediate direct file URL. The user may tap Export Library, then wait for the link to appear, then tap the generated link. Goodreads also indicates users sometimes need desktop site behavior for export.  ￼

So your flow should account for:
	•	generation delay
	•	page refresh state
	•	link appearing later
	•	desktop layout on mobile

That means:
	•	force/request desktop-style rendering if needed
	•	keep the user on the export page with a clear instruction banner
	•	detect the final download event, not just the button press

Parsing strategy

You do not need AI as your primary parser.

Use deterministic parsing first. AI should only be a cleanup layer.

Deterministic parse

The Goodreads CSV usually contains enough structured data to map a lot directly, such as title, author, ISBN, rating, shelves, date added, and date read. Third-party analyses of recent exports describe it as one row per library book with fields like title, author, ISBN, rating, and read-related metadata, though the formatting can be messy.  ￼

Recommended mapping priority
	1.	ISBN13
	2.	ISBN10
	3.	Goodreads book ID if present and you decide to store it as external metadata
	4.	normalized title + normalized primary author
	5.	fuzzy title/author matching
	6.	AI-assisted disambiguation only for leftovers

Normalize aggressively

Goodreads exports are messy. You’ll want to normalize:
	•	quoted ISBN strings like ="0060590297"
	•	blank ISBN fields
	•	date formats
	•	shelves field into array
	•	review text / commas / embedded quotes
	•	duplicate rows or duplicate books across editions

What AI is actually useful for

AI is useful for:
	•	fuzzy resolution of unmatched rows
	•	mapping weird shelf names to your internal model
	•	detecting probable duplicates across editions
	•	generating a confidence score on ambiguous matches

AI is not useful for:
	•	parsing a known CSV schema as the primary path
	•	replacing ISBN matching
	•	doing first-pass import logic

If you rely on AI too early, you’ll create inconsistent imports and ugly trust problems.

Your data model decisions matter more than the parser

Before building, decide how Goodreads concepts map to Spines.

Must-decide mappings
	•	exclusive shelf -> your canonical status?
	•	read
	•	currently-reading
	•	to-read
	•	custom shelves -> tags, collections, or both?
	•	star ratings -> same scale or transformed?
	•	date read -> one date or start/finish dates?
	•	rereads -> one reading event or just latest read date?
	•	review text -> import as note/review/draft?
	•	owned copies -> ignore or map?

One subtle issue: Goodreads export is not perfect historical reading-event data. Some Goodreads community posts note missing detail such as full reread history or started-reading dates in standard export.  ￼

So don’t promise “perfect historical migration.” Promise:
	•	books
	•	statuses
	•	ratings
	•	shelves/tags
	•	dates where available
	•	reviews/notes where available

That’s honest and good enough.

UX details I’d strongly recommend

1. Tell the user exactly what will import

On the entry screen:
	•	books in library
	•	reading status
	•	ratings
	•	shelves/tags
	•	reviews/notes
	•	read/add dates when available

2. Show a post-parse preview

Before commit:
	•	312 exact matches
	•	18 probable matches
	•	9 need review
	•	4 duplicates skipped

This will massively reduce support tickets.

3. Let users choose import behavior

Toggles:
	•	Import shelves as tags
	•	Import ratings
	•	Import reviews
	•	Skip books already in Spines
	•	Merge duplicates automatically

4. Save the raw file and parse result

For debugging and retries.
Absolutely worth it.

5. Build for retries/idempotency

Users will import twice.
You need:
	•	external source record
	•	row fingerprint
	•	dedupe logic
	•	“already imported from Goodreads on [date]”

Biggest technical/product risks

1. Goodreads login + export may be hostile to mobile web

This is probably your biggest risk.

2. Goodreads may require desktop-style experience

So your embedded flow may need:
	•	desktop user agent
	•	explicit “Open desktop site” fallback
	•	alternate button if export controls are hidden

3. Download handling on iOS will be finicky

This is where your engineering time goes.

4. ISBN coverage will be incomplete

You will need good title/author fallback matching.

5. Edition mismatch

One Goodreads row may correspond to a different edition than your catalog’s canonical book.

So architect for:
	•	work-level match
	•	edition-level match
	•	confidence scoring

What I would not do

I would not:
	•	build a “Connect Goodreads account” concept unless you truly have an ongoing sync
	•	imply real Goodreads API integration
	•	make AI the core parser
	•	ship without a manual CSV upload fallback
	•	ship without preview/review for ambiguous matches

Recommended v1 scope

V1
	•	Import from Goodreads CSV
	•	Primary flow: in-app guided export
	•	Fallback: pick downloaded CSV
	•	Exact ISBN + deterministic title/author matching
	•	Preview screen
	•	Import statuses, ratings, shelves, dates, reviews where present
	•	Idempotent dedupe

V1.5
	•	Better edition matching
	•	Better custom shelf mapping
	•	Better duplicate detection
	•	Retry imports from saved raw file

V2
	•	share extension from Files/Safari
	•	“Open in Spines”
	•	maybe broader import sources beyond Goodreads

My actual recommendation

If I were shipping this on iOS, I’d do:

Primary
	•	WKWebView guided export flow
	•	attempt automatic CSV capture using WKDownloadDelegate

Fallback
	•	UIDocumentPickerViewController
	•	plus share extension later

That gives you the slickest experience available without pretending Goodreads has a modern import API.

The key mindset is:
you are not integrating with Goodreads as a platform
you are integrating with Goodreads’ CSV export as a user workflow

That framing will keep the project scoped correctly.

Once you send the screenshots, I can help you design:
	•	the exact iOS flow
	•	the import architecture
	•	the field mapping spec
	•	edge cases
	•	and a PRD-level breakdown with engineering notes

---

## Share Extension setup (implementation notes)

- **App Group** (`group.com.wellread.app`): Must be enabled for both the main app and the Share Extension in [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list). If the extension’s container is null, UserDefaults/app-group file won’t be shared.
- **Keychain Sharing**: Used as a fallback to pass the shared URL from the Share Extension to the main app when the App Group container is unavailable. Both targets have the same keychain access group (`$(AppIdentifierPrefix)com.wellread.app`) in their entitlements. If you archive or run on a real device and see a keychain entitlement error, add **Keychain Sharing** for both App IDs in the developer portal and regenerate provisioning profiles.
- Share extensions cannot open the containing app via `extensionContext?.open(url)`; the main app consumes the pending URL when it becomes active (e.g. user switches to Spines).

## Book covers (Open Library + Google)

- **Order**: For each book with a known ISBN (digits from Goodreads export or Google Books `industryIdentifiers`), cover URLs are tried in order: **Open Library** (`covers.openlibrary.org/b/isbn/{ISBN}-L|M|S.jpg`), then **Google Books** (primary + zoom fallbacks + ID-based URLs).
- **Storage**: `books/{id}` in Firestore may include optional `isbn` (digits only) so covers resolve after sync.
- **Placeholders**: Tiny Open Library “missing” images are rejected so we fall through to Google; Google’s gray placeholders are already filtered in `CoverImageCache`.