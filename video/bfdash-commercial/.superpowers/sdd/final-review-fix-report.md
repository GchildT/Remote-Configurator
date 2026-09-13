# Final Review Fix Report — bfdash-commercial

## Changes by file

### src/components/Caption.tsx
Added a third `position` value, `"center"`, alongside the existing `"top"`/`"bottom"`. The
`"top"`/`"bottom"` branches are untouched (same absolute `left/right: 8%`, `bottom/top: 54%`
positioning ported from the Short). For `"center"`, the outer wrapper switches to
`position: "relative"` (a normal flow block a flex parent can center) with `alignItems: "center"`
and `textAlign: "center"`, and each word-wrap row's `justifyContent` becomes `"center"` instead of
`"flex-start"`. This lets callers in the landscape project center caption text as a flex item
instead of being stuck with the Short's fixed absolute offsets that assumed a portrait container.

### src/components/SplitBeat.tsx
The right-half container (`position: absolute; left: 50%; top: 0; width: 50%; height: 100%`) now
also gets `display: flex; flexDirection: column; alignItems: center; justifyContent: center; gap: 48`.
`BeatIcon` still positions itself absolutely (untouched), so it keeps anchoring near the top; the
`Caption` (now rendered with `position="center"`, a normal flow element) is centered as a group in
the remaining space instead of being independently absolutely-positioned at a fixed 54% offset that
left the bottom half of the column empty.

### src/BFDashCommercial.tsx
- Added `TOTAL_FRAMES = 1350` and `FADE_OUT_FRAMES = 23` constants near the top, and changed the
  audio-fade `interpolate` call from the literal `[1327, 1350]` to
  `[TOTAL_FRAMES - FADE_OUT_FRAMES, TOTAL_FRAMES]`, removing a second, disconnected literal for the
  same total-duration number that `Root.tsx` already owns (`Root.tsx` left untouched as the
  single source of truth for composition duration).
- Photo-beat `Caption` (passed into `SplitBeat`'s `caption` prop) now gets `position="center"`.
- The reveal-caption branch's bare `<AbsoluteFill>` now has `alignItems: "center", justifyContent: "center"`
  and its `<Caption>` uses `position="center"`. Viewed the rendered frame (217) first — the single
  line reads comfortably centered on the full 3840x2160 canvas without touching the edges, so no
  extra `padding` was added (would have been over-engineering beyond what the frame needed).

### src/components/OutroCard.tsx
Replaced the bare `<Caption text={caption} startFrame={0} position="bottom" />` (no centering
parent, left-aligned at 8%) with:
```tsx
<AbsoluteFill style={{ top: "50%", height: "50%", alignItems: "center", justifyContent: "center" }}>
  <Caption text={caption} startFrame={0} position="center" />
</AbsoluteFill>
```
The top-half logo `AbsoluteFill` was left exactly as it was. This puts the logo and caption on the
same horizontal center axis.

### scripts/extract-audio.sh
Added a one-line explanatory comment above the `SOURCE=` line documenting why this project's script
uses a Windows-style path instead of the sibling Short project's Git-Bash-style `/c/...` path
(native Windows ffmpeg build on this machine doesn't resolve `/c/...`). No path value changed.

## Test output

### Before making changes
(Not run — changes were additive/new branches; per task instructions the existing suite was
expected to be unaffected. Ran once, after changes, per Verification step 1.)

### After changes — `npm test`
```
 Test Files  9 passed (9)
      Tests  23 passed (23)
```
All 9 test files / 23 tests passed, including `Caption.timing.test.ts`,
`TitleCard.test.tsx`, `OutroCard.test.tsx`, and `BFDashCommercial.render.test.ts` (renders every
sample frame without throwing). No adjustments were needed — `OutroCard.test.tsx` only checks text
presence/opacity via `getByText`, not the `position` prop used, so it was unaffected by the
`position="bottom"` -> `position="center"` change.

### `npm run typecheck`
Clean (`tsc --noEmit` produced no output/errors).

### Full suite re-run after visual confirmation
Re-run not separately needed since no code changed between the first test run and the still
renders (stills only render existing code) — the same passing result stands.

## Rendered stills

- **Frame 90 (hook, no icon):** Right half now shows the caption ("Tired of tabbing between
  goggles and Betaflight mid-tune?") vertically centered in the available space of the right
  column, no longer stranded around the vertical middle with dead space below it.
- **Frame 416 (feature-pids-sliders, has icon):** Icon (crossed sliders icon) sits near the top of
  the right half as before; caption ("8 PID tuning sliders — matched to Configurator") is centered
  in the remaining space below/around it. Icon + caption now read as one balanced vertical group
  instead of icon-near-top / caption-stranded-mid / empty-space-below.
  ​
- **Frame 217 (reveal-caption):** Single line ("So I vibe-coded my own LUA app.") is now centered
  both horizontally and vertically on the full 3840x2160 black canvas, replacing the previous
  small, left-aligned, ~46%-down placement in an otherwise empty frame.
- **Frame 1305 (outro):** Logo (top half) and "Subscribe for more FPV / Link in Bio - Comments
  Open" caption (bottom half) now share the same horizontal center axis — both are centered on the
  frame's vertical centerline, resolving the previous mismatch (logo centered, caption left-aligned
  at 8%).

Nothing is clipped or overlapping in any of the four frames.

## Files changed
- src/components/Caption.tsx
- src/components/SplitBeat.tsx
- src/BFDashCommercial.tsx
- src/components/OutroCard.tsx
- scripts/extract-audio.sh

## Concerns
None. All changes are additive/style-only, existing "top"/"bottom" Caption behavior is byte-for-byte
unchanged (verified by not touching those branches), and the full test suite plus typecheck pass
cleanly. Visual spot-checks of the 4 requested frames confirm the dead-space/misalignment issues
described in the review are resolved.
