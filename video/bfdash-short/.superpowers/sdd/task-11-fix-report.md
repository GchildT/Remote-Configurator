# Task 11 Fix Report: TitleCard "BFDash" defect + VTX callout misplacement

## Defect 1: TitleCard never actually shows "BFDash"

**File:** `src/components/TitleCard.tsx`

**Root cause:** The component rendered `splash-neontag-blue.png` (the channel's
"DIRTY NACHOS FPV" brand splash) as the visual title, on the mistaken
assumption that this PNG's wordmark spelled out "BFDash". It does not — it
reads "DIRTY NACHOS FPV" with a drone icon and a radio icon. The actual
`title` prop text was rendered into a hidden div
(`opacity: 0, height: 0, overflow: hidden`), so "BFDash" never appeared
on screen anywhere in the video.

**Fix:**
- Shrunk the splash image from `width: 70%` down to `width: 30%` so it now
  reads as a small decorative brand mark rather than the primary title.
- Removed the hidden `<div>` that swallowed the `title` text.
- Added a new visible title `<div>` between the splash image and the
  subtitle, rendering `{title}` with:
  - `fontFamily: "system-ui, sans-serif"`, `fontWeight: 800`, `fontSize: 128`
  - `color: "#ffffff"`
  - `textShadow: "0 0 24px rgba(56, 214, 255, 0.85), 0 0 4px rgba(56, 214, 255, 0.9)"`
    — the same neon-cyan glow language used in `Caption.tsx`.
  - Reused the existing `logoProgress` interpolation (0 to 1 over
    `LOGO_POP_FRAMES` = 15 frames, `Easing.out(Easing.cubic)`) for both
    opacity and a `scale(0.85 -> 1)` pop-in transform — i.e. the same timing
    that used to animate the splash image now drives the title text's
    pop-in, and the splash image keeps that same animation for itself too
    (both pop in together at the start of the beat).
  - The subtitle's animation (`subtitleProgress`, delayed by
    `SUBTITLE_DELAY_FRAMES` = 20, `SUBTITLE_POP_FRAMES` = 15) is untouched.
- Public props (`{ title: string; subtitle: string }`) are unchanged.
  `TitleCard.test.tsx` was not modified; it now finds "BFDash" via
  `getByText` because the real title div renders it, not via the old
  hidden-div trick.

## Defect 2: VTX feature beat's callout box misplaced

**File:** `src/scenes.ts`, `feature-vtx` scene entry.

Updated per the measured coordinates in `public/photos/vtx.jpg` (text block
at x: 12%-25%, y: 34%-51% of frame; tab bar at y: 0-15%):

- `calloutRect`: `{ xPct: 10, yPct: 60, wPct: 60, hPct: 30 }` -> `{ xPct: 8, yPct: 30, wPct: 24, hPct: 24 }`
- `focalPoint`: `{ xPct: 40, yPct: 70 }` -> `{ xPct: 30, yPct: 40 }`

This puts a tight box around the actual "Band: 0 / Channel: 0 / Power: 0"
text (with margin), and keeps both the tab bar and the text block in frame
as PhotoBeat's Ken-Burns zoom scales up via `object-fit: cover` /
`object-position` driven by `focalPoint`.

## Test suite output

`npm test` (full suite, 9 files / 23 tests) — all passed:

```
 ✓ src/scenes.test.ts (2 tests)
 ✓ src/components/Caption.timing.test.ts (4 tests)
 ✓ src/components/CalloutBox.timing.test.ts (4 tests)
 ✓ src/components/PhotoBeat.timing.test.ts (3 tests)
 ✓ scripts/extract-audio.test.mjs (1 test)
 ✓ src/components/TitleCard.test.tsx (1 test)
 ✓ scripts/prepare-photos.test.mjs (6 tests)
 ✓ src/components/OutroCard.test.tsx (1 test)
 ✓ src/BFDashShort.render.test.ts (1 test) 9674ms

 Test Files  9 passed (9)
      Tests  23 passed (23)
```

`npm run typecheck` (`tsc --noEmit`) — passed with no output (no type
errors).

`npm test -- BFDashShort.render.test.ts` (re-run in isolation) — passed,
regenerated `out/frame-samples/frame-{0,150,400,700,850,899}.png`.

## What frame-150.png actually shows (and an important caveat)

`out/frame-samples/frame-150.png` is a **caption** frame ("So I vibe-coded
my own LUA app.") from the `reveal-caption` scene (`startFrame: 120,
durationFrames: 50`, i.e. frames 120-169), **not** the `reveal-title` scene
(`startFrame: 170, durationFrames: 70`, i.e. frames 170-239). The task
description's assumption that "frame 150... is inside the reveal-title
beat" does not match the actual scene timeline in `src/scenes.ts` — this
looks like the same kind of stale assumption noted for Defect 1, just
applied to frame numbers instead of the splash PNG content. `SAMPLE_FRAMES`
in `BFDashShort.render.test.ts` is `[0, 150, 400, 700, 850, 899]`, unrelated
to scene boundaries, and I did not change it (out of scope for these two
defects).

To actually verify the TitleCard fix visually, I rendered an ad hoc still
at **frame 200** (squarely inside `reveal-title`, 170-239) using
`npx remotion still` to a temp file (not committed, deleted after
inspection). That frame shows:
- The small "DIRTY NACHOS FPV" splash logo near the top-center (decorative,
  now ~30% width instead of 70%).
- A large, bold, white "**BFDash**" title directly below it, with a clearly
  visible cyan/blue neon glow (`textShadow` halo) around the letters —
  fully readable and prominent.
- The subtitle "Remote Betaflight Configuration Dashboard" below that, in
  the smaller cyan glow style, unchanged from before.

This confirms Defect 1 is fixed: "BFDash" is now an actual, prominent,
readable on-screen title in the reveal-title beat.

I also spot-checked the `feature-vtx` scene at frame 580 (within its
540-614 range) with a similar ad hoc still render. The callout box now
sits in the upper-left area of the frame, tightly bounding the
"...0 / ...nel: 0 / ...er: 0" text lines (partially cropped further left
by the Ken-Burns zoom/crop at that point in time, which is expected/normal
zoom behavior, not a callout misplacement), rather than the old box that
sat in empty lower-frame space. This matches the exact `calloutRect`/
`focalPoint` values specified in the task.

## Files changed

- `src/components/TitleCard.tsx` — Defect 1 fix.
- `src/scenes.ts` — Defect 2 fix (`feature-vtx` scene only).

No other files were modified. `TitleCard.test.tsx` was read but not
touched, per instructions. `out/frame-samples/*.png` are regenerated
build artifacts (not committed — verified via `git status`, they don't
appear as tracked/untracked-to-add changes).

## Concerns

- The frame-150.png inspection step as literally specified in the task
  does not show the title card (it shows a caption from the preceding
  scene), because frame 150 falls in `reveal-caption` (120-169), not
  `reveal-title` (170-239). I verified the actual fix using an
  out-of-band still render at frame 200 instead, and documented the
  discrepancy above rather than silently substituting or altering
  `SAMPLE_FRAMES` in the test (which was out of scope for the two defects
  described). If the sample-frame list should be corrected to actually
  cover the reveal-title beat, that would be a separate, follow-up fix.
- No other concerns; both fixes are minimal, scoped, and all existing
  tests (including the full render integration test) pass.
