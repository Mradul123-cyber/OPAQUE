# OPAQUE UI implementation

## Isolated workspace

Original: `E:\Zarq Final\zarq_git\zarq_messenger`
Working copy: `E:\Zarq Final\zarq_git\opaque`
Repository requested: public `Mradul123-cyber/opaque`. GitHub creation/push still pending authenticated access. Local branch: `main`.

The authoritative working copy is the E: drive location above. The earlier D: drive copy is superseded and must not be used for implementation.

The working copy includes the original uncommitted modifications, untracked source files, and tracked deletions. All 93 files under lib matched the original by SHA-256 before UI implementation. Existing Git differences are inherited user work, not redesign changes. Generated build, dependency and plugin cache directories were excluded from the copy. Style and the shared header are now implemented. Pre-edit snapshots are under `design-reference/before-style-header`. Other screen redesigns remain pending.

## Approved reference

`opaque-preview.html` is the unified interactive design reference. Implement Home, Chat, Calls, Friends, and Style. Preserve Notes for a later code-informed design pass. Demo data and preview-only controls must not enter the production UI.

Rebrand visible UI to OPAQUE; retain internal zarq identifiers, Android application ID, Firebase configuration, storage names, encryption and service behavior.

## Preserve existing actions

Home popup: Settings, Call History, About, Logout.
Chat popup: Search, Mute notifications, Change wallpaper, Clear chat, and conditional Block/Unblock user for individual conversations.
Preserve existing confirmation dialogs, routing and callback implementations. The prototype menus are incomplete representations, not replacement feature specifications.

## Implementation approach

Inspect each screen's complete widget tree and state/callback dependencies before edits. Reuse real conversation, friend/request, call-history and settings providers. Keep E2EE, authentication, backup, media, notifications and networking logic intact. Style supports existing persisted theme, bubble shape and gradient settings; map UI choices to supported stored values. Verify existing call overlay implementations before adjusting their presentation or default.

First establish analysis/build baseline in this copy. Then implement shared visual components and screen-specific layouts. Validate the five screens, dark mode, navigation and existing menu actions. Run Flutter analysis and an Android debug build; report pre-existing versus new diagnostics separately. Do not install a same-application-ID APK over the user's working app without coordinating that step.

Style/header verification: three widget tests passed and debug APK build succeeded. Home, Chat, Calls and Friends implementation is pending; Notes remains deferred.

Style correction (2026-09-18): the approved HTML remains unchanged. Production Style exposes only Light/Dark, Soft/Rounded/Squared, the separate five-colour start/end palettes, and Circular bubble/Horizontal bar. Removed the obsolete customization screen and updated Home and Settings to StyleScreen. Rounded uses uniform 21px corners; Squared uses uniform 7px corners; Soft uses the reference's small top corner. Preview and chat share the shape helper. Saved preference keys and Notes/group behavior are preserved. Eight focused tests pass. Historical snapshots are excluded from analysis.

Repository verification: Mradul123-cyber/opaque exists and is public, but its branches API returned no branches and this local copy has no remote configured; push remains pending.

User instruction: do not build APKs from now on; the user builds manually. Validate changes using analysis and focused tests only. Friends and the five-destination bottom navigation are the active redesign scope.

Friends/navigation implemented: four full-width icon tabs in My Friends / Received / Sent / Find Friends order; embedded Friends uses the shared Home header with no duplicate heading. Compact real-data rows show names, usernames and available contact phone numbers; existing accept/decline/send/message/remove callbacks retained. Sent requests remain a pending indicator because the existing app has no cancellation endpoint. Bottom navigation now has Chats / Calls / Friends / Style / Notes; group creation remains reachable via the home-only expanding Add friend / New group menu. No APK built, per user instruction. The approved HTML remains unchanged.

Calls/nav refinement: removed bottom-navigation tap ripple while retaining keyboard focus; Friends and Notes now use official Lucide contact-round/notebook-pen paths. Calls uses real service records, descending date groups, compact rows, real voice/video callbacks, pull-to-refresh and centered empty state. Embedded Calls uses Home's shared header. No tests, analysis or APK build run, per user preference.

Home redesigned from approved HTML: compact 36px search, All/Unread/Groups filters, live filtering and descending latest-message order, 44px avatars and unread dots, continuous list and compact animated Add friend/New group menu. Existing profile/menu, offline chat opening, typing/online indicators and group long-press actions preserved. No tests or APK build, per user instruction.

Chat redesigned to the approved reference: compact solid header, shared saved bubble shapes/colours, soft incoming bubbles, left-aligned time and inline sent/delivered/seen status, compact composer, and six-option attachments below it. Gallery/Camera preserve both photo and video via a media-type chooser; Documents retains its sender. Contact/Location/Poll are unavailable pending product decisions. AI shows only a three-second Coming soon snackbar. Existing replies, recording, calls, message selection and menu callbacks retained. Home + Add friend now selects embedded Friends/Find Friends under the common OPAQUE header. Default blue applies only without saved colours. No tests, analysis or APK build run, per user instruction.

Notes implemented from the approved standalone preview: shared header and navigation, compact search/category filters, pinned-first list, note actions, theme-aware editor, and live body word/character counters. Characters include spaces and exclude Quill's terminal newline. Existing storage, formatting/tasks, categories, flowcharts, and protection retained. Preview counters updated. No tests, analysis or APK build run per user instruction.

Notes protection now follows the approved preview in light/dark mode: settings sheet, setup, unlock, change with confirmation, disable with verification, inline validation, password visibility, and locked Notes surface. Uses the existing NotesPasswordService and credentials. No tests or APK build run.

Chat sharing UI: contact picker/search and selected-number review, compact contact cards with filled Call/Save icon buttons, full-page poll composer and simple live-vote cards, and GPS location review redesigned. Existing encrypted payload methods retained. User explicitly approved external coordinate/query sharing. OpenStreetMap tiles, Nominatim submitted search, and Overpass nearby places are now integrated, including selectable map pins, distance labels, GPS refresh and message maps. Endpoints can be configured with OPAQUE_MAP_TILE_URL, OPAQUE_PLACE_SEARCH_URL and OPAQUE_NEARBY_URL. Search requests are throttled and cached; map tiles use flutter_map 8.2.2 caching and visible attribution. No tests or APK build run.

About preview (2026-09-20): added to the unified opaque-preview.html reference; open with #about or Home menu > About. Includes a neutral logo placeholder, light/dark preview control, version 1.0.0 build 27 from pubspec, and the three existing legal/support document routes. Documents show existing source text with a branding-pending label. Flutter About implementation remains unchanged; this is a browser design proposal only.

About logo direction: the final OPAQUE logo will be circular. Keep the About placeholder circular until the logo asset is decided.

About logo review: concept 09 (Conversation O — Soft) now appears in the circular 74px About logo area. CSS frames the primary badge from the original concept sheet without altering the image. Preview only; final logo approval and production asset preparation remain pending.

Logo review update: concept 13 replaces concept 09 in About. User found nested circular O shapes confusing and prefers a squared inner form within a circular badge. Preview now uses a solid rounded-square conversation bubble; previous concepts retained for comparison.

Logo direction correction: user wants one hollow rounded-rectangle O, tilted, inside a circular badge. Concept 14 now appears in About for review, replacing the solid bubble interpretation. No additional ring or speech bubble.

Logo review concept 15: refined the user's first attached interlocking mark with rounded terminals, balanced weight and clearer gaps. Now displayed in About; earlier concepts preserved. Preview only.
