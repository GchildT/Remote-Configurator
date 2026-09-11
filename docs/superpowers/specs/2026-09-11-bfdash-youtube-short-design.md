# BFDash YouTube Short — Design

## Purpose

A 30-second YouTube Short introducing BFDash (the Betaflight Settings Dashboard
for EdgeTX LUA app documented in this repo's [README](../../../README.md)) to
drive awareness and pilot feedback, per the announcement already posted to the
project's internal Discord:

> I tend to build and tune various sized drones on a regular basis. I got
> tired of either using my goggle or going back and forth to Betaflight during
> tuning sessions just to change settings for LOS tuning runs. I know there
> may be some out there already, but I vibe coded my own LUA App to Configure
> / Change some betaflight settings for tuning. You also can just use it to
> change settings on the fly when you're in the field. If your radio is
> compatible, please test and give me some feedback. I've tested on my Jumper
> T15 and a RadioMaster TX15. Right now for touch / Rotary only. Requirements
> are in the GIT Readme.

## Source Assets

- **Photos** (`C:\Users\gchil\Downloads\Compressed\Photos-1-001_2\`, 8 files):
  real phone photos of a Jumper T15 screen running BFDash — Tools menu
  (BFDash listed among other apps), PIDs tab (slider view and live
  P/I/D/D-Min/FF numeric view), Rates tab, Filters(G) tab, Filters(P) tab,
  VTX tab, Motor tab. These are off-axis phone captures with glare,
  fingerprints, and rotated orientation — not clean screenshots.
- **Brand assets** (`C:\Drone\DirtyNach0s_FPV\branding\output\`): neon-blue
  variant only — `splash_neontag_blue.png`, `pfp_neontag_blue.png`,
  `banner_neontag_blue.png`, `background_t15_blue.png`. "DIRTY NACHOS FPV"
  wordmark with a drone-icon (X with 4 circles) and a radio-icon (rounded
  square with crosshair), both neon cyan on dark navy.
- **Audio**: `C:\Drone\Music\Tame Impala - Cause I'm A Man.flac` (from the
  album *Currents*, 2015; full duration 4:02). Trim to the 30-second window
  **1:11–1:41** for use as the short's music bed. This is commercially
  released music with no license secured — using it will very likely trigger
  a YouTube Content ID claim (revenue redirect to the rights holder, possible
  regional restrictions). Proceeding is a deliberate choice made by the
  project owner, not a default recommendation.
- No voiceover, no existing outro clip (the "shorts outro" branding folder is
  empty) — the outro is built fresh in Remotion from the brand assets above.

## Format

- Vertical 4K: 2160×3840, 30fps, 900 frames (30 seconds total).
- Captions/on-screen text only — no spoken narration.

## Structure & Timing

Approximate beat timing (exact frame numbers finalized during implementation
against the trimmed audio's actual beat/onset positions):

| Beat | Time | Content |
|---|---|---|
| Hook | 0:00–0:04 | Rates tab photo, slow moody Ken-Burns zoom. Caption: "Tired of tabbing between goggles and Betaflight mid-tune?" |
| Reveal | 0:04–0:08 | Caption "So I vibe-coded my own LUA app." → title card **BFDash** with subtitle "Remote Betaflight Configuration Dashboard" |
| Feature rip | 0:08–0:23 | 6 beats, ~2.5s each (see below) |
| Payoff | 0:23–0:26 | "Change it in the field. No goggles. No laptop. No USB." |
| CTA | 0:26–0:28 | "Tested on Jumper T15 & RadioMaster TX15 — try it, tell me what breaks." |
| Outro | 0:28–0:30 | Logo convergence sting + "Subscribe for more FPV builds & tuning" / "Link in bio · comments open" |

### Feature rip beats (in order)

1. PIDs sliders photo — "8 PID tuning sliders — matched to Configurator"
2. PIDs numeric photo — "Live P / I / D / D-Min / FF preview"
3. Rates photo, cropped to the numeric grid (callback to the hook shot, now
   showing the actual data) — "All 4 rate types, every axis"
4. Filters(G) and/or Filters(P) photo — "Gyro + D-term filters — global &
   per-profile"
5. VTX photo — "Band, channel, power"
6. Motor photo — "Throttle boost, idle, sag comp"

## Visual & Animation Style

- **Photo treatment**: each source photo is rotated/cropped/de-skewed once
  (pre-processing pass, not live CSS transforms, since these are off-axis
  phone captures) so the radio screen fills the frame and text reads level.
  Cool color grade (deepened blues/blacks, lifted on-screen text contrast) to
  mask glare and match the brand palette. Continuous slow Ken-Burns drift
  (scale 1.0→1.08 with slight pan) on every beat. Soft vignette + faint
  scanline/glow overlay ties the photos to the neon-tag branding.
- **Callout boxes**: animated rounded-rect outline (brand cyan, glowing
  stroke) draws itself around the specific on-screen value being called out —
  scale+fade in (~150ms), holds, fades on cut. No arrows/pointers.
- **Captions**: bold condensed sans, white with subtle cyan glow/drop-shadow,
  lower-third placement. Words pop in with upward slide + scale, staggered
  ~40ms per word.
- **Transitions**: hard cuts on the beat; each incoming photo's Ken-Burns
  starts from a slightly wider scale (1.1→1.0 snap-in) so cuts carry a small
  punch-in feel.
- **Title card**: styled to match `splash_neontag_blue.png` — drawn-on stroke
  animation for the drone/radio icons, wordmark scales+glows in beneath, full
  name subtitle glows in just after.
- **Outro**: reuses the same icon/wordmark assets — icons converge toward
  center, wordmark glow pulses once, subscribe/CTA captions stack below in
  the same caption style used throughout (visual consistency, not a separate
  outro look).

## Audio

- Music bed: the trimmed 1:11–1:41 Tame Impala clip, used as the full 30s
  bed. Cut points and caption pop timing are synced to this segment's actual
  beats/onsets (extracted from the real audio, not assumed BPM), with the
  Reveal/BFDash title-card hit aligned to the nearest strong beat after 0:04.
- SFX layered under the music: soft whoosh on each callout box draw-on, quiet
  UI tick on each caption word-pop, a slightly bigger whoosh/impact on the
  Reveal title-card hit and the Outro logo pulse.
- No voice track.

## Technical Approach

- New Remotion project under `video/bfdash-short/` in this repo. Composition
  `BFDashShort`, 2160×3840, 30fps, 900 frames.
- Source photos pre-processed once (rotate/crop/de-skew via a one-time
  script pass) into cleaned stills under `public/photos/`. Audio trimmed once
  via ffmpeg into `public/audio/hook-track.mp3` (or wav).
- Single data-driven `scenes.ts` array drives the edit: each entry is
  `{ startFrame, durationFrames, type: 'hook' | 'reveal' | 'feature' |
  'payoff' | 'cta' | 'outro', image?, caption, calloutRect? }`. The root
  `<BFDashShort>` component maps this array to `<Sequence>` blocks, so
  re-timing a beat, swapping a photo, or editing caption text is a one-line
  change.
- Shared components, each with one clear purpose:
  - `PhotoBeat` — Ken-Burns zoom/pan + color grade + vignette on one image,
    optional `CalloutBox` overlay.
  - `CalloutBox` — glowing rounded-rect draw-on, positioned by `{x, y, w, h}`
    percentages.
  - `Caption` — word-pop-in text, reused for every caption line including
    reveal/CTA/outro.
  - `TitleCard` — the BFDash + subtitle reveal, built from the logo
    SVGs/PNGs.
  - `OutroCard` — logo convergence + subscribe/CTA captions.
- Consistent easing (`interpolate` + `Easing.out(Easing.cubic)`) across all
  components for zooms and pop-ins, so the motion reads as one system.
- Render via standard `remotion render` to H.264 4K, following the
  remotion-render skill's guidance for concurrency/quality settings.

## Out of Scope

- Non-touch/jog-dial-only radio demonstration (not shown in the source
  photos, not part of this short's message).
- Any footage of BFDash controlling a flight controller mid-flight (LOS
  tuning use case is described in captions, not shown — no flight footage was
  provided).
- Licensing/clearing the Tame Impala track — explicitly deferred to the
  project owner's judgment (see Source Assets).
