# Workout share card and PR celebration — design

Status: draft for owner approval (2026-10-29), reviewed by a builder check. Becomes a GitHub spec issue with tickets once approved.

## Intent

After finishing a workout, a lifter wants to show it off, mainly as an **Instagram Story to friends**. MAYOS gives them a finish moment and a ready-to-post image:

1. If the workout set a **personal record**, a short celebration plays (confetti + trophy) before the summary.
2. From the summary, the lifter makes a **share card**: a 9:16 image of their own photo with the MAYOS logo and the session's stats on top, and shares it through the phone's share sheet.
3. The same card can be made **later for the most recent workout**, from Home's latest-session card.

Success: lifters post their sessions, which shows MAYOS to their friends. The card looks good enough to post without editing.

## Owner decisions

- Target: Instagram Stories (9:16 portrait image). Other share targets come free through the share sheet.
- Photo: take one with the camera **or** pick one from the gallery. Either gives the same card.
- Card content: MAYOS logo, **day name**, **duration**, **volume**, **sets**, **PRs**.
- **Never show body weight** on the card, under any setting.
- PR celebration: a **quick burst** (confetti and trophy, about 2 seconds), then the summary. It does not wait for a tap.
- PRs on the card appear as a **badge with a count** ("🏆 2 PRs"), as in the approved mockup. The summary screen keeps listing each PR in full.
- Available **right after finishing** (from the summary) **and later for the last workout**: a Share action on Home's latest-session card. A full workout History for lifters is out of scope (owner chose this 2026-10-29).
- Approved layout: see the mockup at `.superpowers/brainstorm/*/content/share-flow.html`, also described below.

## Layout (approved mockup)

- **Celebration:** full screen over the dark canvas. Confetti in brand blue `#2F6BFF`, gold and white. A trophy in the centre, "New PR!" and the top PR ("Bench Press · 100 kg × 5"). Plays only when the finished workout has at least one PR, then goes straight to the summary.
- **Summary:** the existing post-Finish summary, plus a primary **Share to Story** button above Done.
- **Card (1080×1920):**
  - Photo full-bleed, with a dark gradient at the bottom for legibility.
  - MAYOS logo at the top-left: the white M-mark lockup or wordmark from `mobile/assets/brand/`.
  - At the bottom, in order: a PR badge (only when PRs > 0), the day name large, then a row of three stats (duration, volume with unit, sets).

## Calls made by Claude (owner to check)

- **Sharing:**
  - Android uses the system share sheet with the image file (Instagram, WhatsApp, Save, …). We don't integrate Instagram's API.
  - On the web app, use the Web Share API with a file where `navigator.canShare({files})` allows it, otherwise download the PNG.
- **Privacy:** the photo and the card are made and kept **on the device only**. Nothing is uploaded to the API, the coach, analytics or the model. This keeps ADR 016's training-data boundary intact.
- **No-photo card:** if the lifter skips the photo, the card renders on a dark MAYOS background (wallpaper or gradient) with the same layout.
- **Units and language:**
  - Volume is in kg; the app has no unit setting today, so this feature doesn't add one. It's rounded with a thousands separator. Duration is shown as `58m` or `1h 12m`.
  - Card text (labels, "New PR!") follows the display language; Arabic uses the existing catalog with RTL layout. The logo and digits stay Latin, as elsewhere in the app.
- **Day name:** the program day name the workout was logged against, e.g. "Push A". If only the generic fallback `'Day'` is available, the card leaves the day name out rather than printing "Day".
- **Stats source:**
  - After Finish: the existing `workoutSummaryStats` / `WorkoutSummary` (working sets, warm-ups excluded; volume Σ kg × reps over ticked working sets; duration).
  - From Home: the latest session as Home already loads it (`/sessions/latest`).
- **PRs on the later card:** the count is the records **that workout set at the time**, not records still standing today. The server's append-only `personal_records` rows carry `session_id`, so this is one query, added to the `/sessions/latest` payload.
- **When Share appears:** only once the workout is saved, including a local Android save that is still waiting to sync. A workout that is later discarded can't produce a card, and the analytics event never counts one.
- **What "PRs" counts:** the badge counts **exercises that set at least one record** in the workout, so a set that beats both heaviest weight and best e1RM still counts as 1. The celebration's headline record is the heaviest-weight record first, then e1RM, then most reps. `WorkoutRecord` gains the set's reps so the celebration can show "100 kg × 5".
- **Cardio:** for a cardio-only workout, the card shows cardio minutes in place of volume and sets. With mixed cardio and lifting, the card shows the lifting stats only. **Calories never appear on the card**, the same as body weight.
- **Celebration only after Finish,** never when opening a past workout.
- **Celebration accessibility:** respects the OS "reduce motion" setting by showing the trophy without confetti for the same short time.
- **Edits before sharing:** none in v1. No stat toggles, filters or stickers.
- **Analytics (PostHog, existing opt-out rules):** `share_card_shared` with `source` (finish|home), `has_photo` (bool) and `photo_source` (camera|gallery|none). No image and no stats values.
- **Permissions:** request camera or photo access only when the lifter chooses that option, using the platform's standard flow. If access is denied, the no-photo card stays available.
- **Feature list / What's new:** add a lifter entry per `docs/agents/issue-tracker.md` (new release), with EN + AR copy.

## Non-goals

- Instagram or TikTok API integration, or posting on the lifter's behalf.
- Storing cards or photos on the server, or a public share link.
- Video or animated cards.
- Coach-side sharing, or cards for Coach mode.
- A workout History list for lifters, or sharing workouts older than the latest.
- Editing stats or adding stickers/text in v1.

## Anti-goals (would make it a failure even if it works)

- Body weight, or any health or clinical data, ever appears on a card.
- The photo leaves the device.
- The celebration blocks or delays saving the workout, or plays when there was no PR.
- The card looks cheap: stretched photo, unreadable text over a bright photo, cut-off numbers in Arabic or at 2× text scale.

## Constraints

- **Flutter app:** the same feature on Android and the web app (PWA). The web app must stay CSP-safe: no new external origins, and the image is made in the browser.
- **New packages:** expect a camera/gallery picker and a share plugin (e.g. `image_picker`, `share_plus`). They must support Android and web, and Android permission strings go in the manifest.
- **Repo conventions:**
  - Never run `dart format` on existing files.
  - Write tests first, describing behaviour.
  - Player-visible copy gets EN + AR entries in the existing catalogs.
- **Offline:** making and sharing the card works fully offline right after Finish, before the workout has synced.

## Left to the builder

- How to render the card off-screen (e.g. `RepaintBoundary` → PNG at 1080×1920), and how to fit and crop the photo (cover crop, centred).
- The confetti implementation: a small custom painter is preferred over a heavy package.
- How the work splits into tickets. Suggested: (1) card rendering + share with the no-photo background; (2) camera and gallery photo; (3) PR celebration; (4) Home latest-session entry point + PRs on `/sessions/latest`; (5) What's new + analytics.
