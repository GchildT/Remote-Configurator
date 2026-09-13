# BFDash 4K Commercial (Left/Right Split) — Design

## Purpose

A 45-second, 4K landscape (16:9) YouTube video reusing the same script,
photos, audio, brand assets, and beat icons as the vertical YouTube Short
([2026-09-11-bfdash-youtube-short-design.md](2026-09-11-bfdash-youtube-short-design.md)),
laid out for landscape viewing as a "commercial"-style piece: left/right
split instead of top/bottom, same content stretched to a more relaxed pace.

## Relationship to the Short

This is a sibling deliverable, not a variant flag on the existing project.
The Short (`video/bfdash-short/`) is finished and approved; this project
does not modify it. Where content is identical (captions, calloutRect
values, icon choices, photos, logos, music track) it is copied over
verbatim or re-derived from the same source, not re-authored.

## Format

- 3840×2160 (4K, 16:9 landscape), 30fps, 1350 frames (45 seconds).
- New git branch/worktree off `master`, parallel to (not built on top of)
  the `worktree-bfdash-youtube-short` branch already merged to `master`.

## Timeline

Every beat from the Short is kept, in the same order, with the same
caption text, stretched ×1.5 (45s / 30s) from its original frame count.
Feature-beat durations are rounded to whole frames alternating
112/113 so the six of them still sum exactly to 675:

| Beat | Start | Duration | Caption (verbatim from the Short) |
|---|---|---|---|
| hook | 0 | 180 | "Tired of tabbing between goggles and Betaflight mid-tune?" |
| reveal-caption | 180 | 75 | "So I vibe-coded my own LUA app." |
| reveal-title | 255 | 105 | "BFDash" / "Remote Betaflight Configuration Dashboard" |
| feature-pids-sliders | 360 | 113 | "8 PID tuning sliders — matched to Configurator" |
| feature-pids-numbers | 473 | 112 | "Live P / I / D / D-Min / FF preview" |
| feature-rates-data | 585 | 113 | "All 4 rate types, every axis" |
| feature-filters | 698 | 112 | "Gyro + D-term filters — global & per-profile" |
| feature-vtx | 810 | 113 | "Band, channel, power" |
| feature-motor | 923 | 112 | "Throttle boost, idle, sag comp" |
| payoff | 1035 | 135 | "Change it in the field.\nNo goggles. No laptop. No USB." |
| cta | 1170 | 90 | "Tested on Jumper T15 & RadioMaster TX15 —\ntry it, tell me what breaks." |
| outro | 1260 | 90 | "Subscribe for more FPV\nLink in Bio - Comments Open" |

Total: 0+180+75+105+113+112+113+112+113+112+135+90+90 = 1350 frames. ✓

## Layout

**Photo beats** (hook, the 6 feature beats, payoff, cta): **left half of the
frame shows the full, uncropped photo; right half shows the beat icon (for
feature beats only) and caption text.** This mirrors the Short's
top=caption/bottom=photo split, rotated 90°.

- The photo is displayed via the same "contain" principle as the Short
  (no cropping, ever) — sized to fit fully within its half, letterboxed on
  whichever axis has leftover space. The left half's box is 1920×2160
  (AR 0.8889); since every source photo is 3840×2880 (AR 1.3333, wider
  than the box), the photo is width-constrained: full width of the half,
  height = (0.8889 / 1.3333) × 100% ≈ 66.7% of the half's height,
  vertically centered (letterboxed top/bottom within the left half, not
  left/right — the reverse of the Short's math, since the box shape
  itself is different, but the same underlying `contain` principle).
- `calloutRect` values (image-relative percentages of the photo content,
  e.g. `{ xPct: 9, yPct: 40, wPct: 30, hPct: 37 }` for the PIDs sliders
  beat) are copied verbatim from the Short's `scenes.ts` — they describe a
  position on the photo itself, not the frame, so they need no
  recalculation for the new box shape.
- The right half holds, for feature beats only, the same draw-on line icon
  used in the Short (sliders/grid/gauge/funnel/signal/propeller), stacked
  above the caption text, using the same icon component and timing
  constants. Hook/payoff/cta show caption text only on the right half, no
  icon (matching the Short, which also omits icons on those three beats).
- `dim` (the darkened overlay) still applies to payoff and cta, same as
  the Short, since both reuse `motor.jpg`.

**Non-split beats** (reveal-caption, reveal-title, outro): stay as centered,
full-frame lockups — a logo/text composition, not a photo-vs-caption
split, so there's nothing to divide left/right. They adapt naturally to
the wider 16:9 canvas (the existing centered-flex layouts don't assume a
particular aspect ratio); font sizes and logo widths are checked visually
during implementation and adjusted only if something looks stretched or
cramped at the new proportions, not redesigned.

## Assets

- **Photos**: the same 6 processed photos from the Short
  (`tools-menu.jpg` unused, same as the Short) — copied into this
  project's own `public/photos/`, not re-processed (no new rotation/crop
  work needed; they're already the full, uncropped, upright versions).
- **Icons**: same 6 draw-on line icons (sliders, grid, gauge, funnel,
  signal, propeller), same component logic and timing constants.
- **Brand logos**: same `splash-neontag-blue.png` (TitleCard) and
  `pfp-neontag-blue.png` (OutroCard).
- **Music**: `C:\Drone\Music\Tame Impala - Cause I'm A Man.flac`, trimmed
  to **1:11–1:56** (45.000s) instead of the Short's 1:11–1:41 — same start
  point, extended forward. Same Content-ID caveat as the Short applies
  (commercially released track, no license secured — the project owner's
  deliberate choice, not a default).
- **Fade-out**: scaled proportionally from the Short's last-15-frames
  (of 900) fade to the last 23 frames (of 1350): volume ramps 1→0 from
  frame 1327 to frame 1350.

## Technical Approach

- New sibling Remotion project: `video/bfdash-commercial/` (own
  `package.json`, own `node_modules`, independent of
  `video/bfdash-short/`).
- Follows the same pure-timing-function / thin-component pattern
  established in the Short: animation math lives in `*.timing.ts` files,
  unit-tested with Vitest without a Remotion rendering context; components
  are thin wrappers.
- New components (this project's own, not shared/imported from the Short,
  per the "sibling, not variant flag" decision above):
  - `SplitBeat` — this project's analog to the Short's `PhotoBeat`:
    renders the left-half photo container (with the recomputed contain-fit
    math for the 1920×2160 box) and, as children, the optional
    `CalloutBox` (positioned using the same image-relative percentages)
    and the right-half icon+caption stack.
  - `Caption`, `BeatIcon`, `CalloutBox`, `TitleCard`, `OutroCard` — ported
    from the Short with only the geometry constants that depend on frame
    aspect ratio adjusted (if any turn out to need it); text, colors,
    timing constants, and animation curves are unchanged.
- `scenes.ts` — same shape as the Short's (scene id, type, timing, caption,
  image, calloutRect, icon), with the frame numbers and durations from the
  Timeline table above.
- Asset prep: a one-time copy script (or manual copy, since no
  reprocessing is needed) brings the 6 photos and brand PNGs into this
  project's `public/`; a new `extract-audio.sh` trims the 1:11–1:56 window
  from the same source FLAC into this project's `public/audio/`.
- Render via standard `remotion render` to H.264 4K, same as the Short.

## Out of Scope

- A landscape-specific thumbnail (the existing vertical thumbnail concept
  — Betaflight/EdgeTX logo fusion — is a Short-specific deliverable and
  not part of this request).
- Any new copy, beats, or icons beyond what the Short already has —
  "same script" means reused verbatim, not rewritten for the new format.
- Modifying `video/bfdash-short/` in any way.
