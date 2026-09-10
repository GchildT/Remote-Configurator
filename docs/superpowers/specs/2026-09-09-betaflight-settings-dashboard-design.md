# EdgeTX Betaflight Settings Dashboard (LUA Tools Script)

Date: 2026-09-09

> **Status note (kept for history, not current scope):** this spec captures
> the *original* design as authored before implementation began. Scope has
> grown substantially since through real-hardware bench testing and follow-up
> requests: jog-dial editing, a live PID preview, dynamic notch filter tuning
> (explicitly out-of-scope below), a full Motor/Throttle tab, an API-version
> compatibility gate (not the 4.5.x-only firmware-version check described
> here), automatic flight-controller disconnect/reconnect handling, and a
> post-save confirmation. **[README.md](../../../README.md) at the repo root
> is the current source of truth for what the script actually does and
> supports** -- read this file only for the historical reasoning behind the
> original design decisions.

## Context

Jumper T15 radio, EdgeTX 2.9+ (color LCD, 480x272), ExpressLRS (CRSF) link to
FPV drones running Betaflight 4.5.x. Goal: a custom LUA Tools script that reads
and writes Betaflight FC settings over MSP-over-CRSF telemetry, without needing
a USB connection to Betaflight Configurator.

## Scope

A general settings dashboard covering:

- **PID gains** — via Betaflight's actual master-slider algorithm (not raw
  per-axis numeric entry)
- **Rate profiles** — all four rate types (Actual, RaceFlight, KISS,
  Betaflight-classic), selectable
- **Filters** — gyro and D-term lowpass cutoff frequencies only (no dynamic
  notch tuning)
- **VTX** — power level, band, channel

Across selectable PID profile and rate profile slots (1-3).

Out of scope for this version: dynamic notch filter settings, in-flight
tuning (arm-lock blocks edits while armed), any settings categories beyond
the four above.

## Architecture

```
main.lua                - entry point: connection check, tab bar, page router,
                           Save/Cancel/Reload footer
transport/mspChunk.lua  - CRSF MSP chunk framing: builds/parses the status-byte
                           chunk header (seq/start/version/error bits) used by
                           crossfireTelemetryPush/Pop, per Betaflight's
                           telemetry/msp_shared.c wire format
transport/msp.lua       - session layer: request/response matching by command
                           id, polling, timeouts, retry
transport/mspBuffer.lua - generic "patchable message" codec: GET a message's
                           raw response bytes, read/write specific fields by
                           byte offset, SET back the full same-length buffer
                           unchanged elsewhere (used for SIMPLIFIED_TUNING,
                           RC_TUNING, FILTER_CONFIG — all confirmed
                           round-trip-symmetric in firmware source)
mspMsgs.lua              - message-specific field offset tables + FC
                           compatibility check (API_VERSION/FC_VARIANT/
                           FC_VERSION) + bespoke VTX_CONFIG encode/decode
                           (its SET wire format differs from its GET format)
                           + profile select + EEPROM_WRITE
state.lua               - in-memory model: last-read FC values, staged
                           (unsaved) edits, dirty flag, selected PID/rate
                           profile slot
safety.lua              - arm-status detection by parsing the CRSF
                           FLIGHT_MODE telemetry frame (type 0x21) directly;
                           fail-safe treats an unreadable/missing frame as
                           armed
pages/pids.lua           - PID slider screen
pages/rates.lua          - rate screen (rate-type selector)
pages/filters.lua        - gyro/D-term lowpass cutoff screen
pages/vtx.lua            - VTX power/band/channel screen
```

Each page module exposes `create()`, `update(staged)`, `event(...)` and reads
/writes only through `state.lua` — pages never touch the MSP layer directly.
This keeps the risky wire-protocol code in one place, testable independently
of UI.

**Protocol verification addendum (2026-09-09):** the MSP-over-CRSF chunk
framing, every message's exact byte layout, and the CRSF FLIGHT_MODE arm
convention below were pulled directly from the Betaflight 4.5.5 firmware
source (`telemetry/msp_shared.c`, `msp/msp.c`, `msp/msp_protocol.h`,
`telemetry/crsf.c`) rather than derived from memory or an existing
third-party script, since getting this wrong is safety-relevant. Two
corrections to the original design worth calling out:

- **No client-side PID slider math is needed.** Betaflight 4.5 exposes the
  simplified-tuning slider values directly via `MSP_SIMPLIFIED_TUNING` (140)
  / `MSP_SET_SIMPLIFIED_TUNING` (141) — the firmware itself computes the
  resulting per-axis P/I/D/F from the 8 slider percentages
  (`simplified_pids_mode`, `simplified_master_multiplier`,
  `simplified_roll_pitch_ratio`, `simplified_i_gain`, `simplified_d_gain`,
  `simplified_pi_gain`, `simplified_dmin_ratio`, `simplified_feedforward_gain`,
  `simplified_pitch_pi_gain`). We read/write these raw U8 percentages only —
  no formula to port or independently test. This removes the `pidSliders.lua`
  module from the original architecture entirely.
- **Arm status comes from the CRSF FLIGHT_MODE frame, not MSP_STATUS.** The
  MSP_STATUS arming bit lives in a dynamically-ordered bitmask
  (`packFlightModeFlags`) whose bit position isn't a fixed constant, so it
  can't be safely hardcoded. Instead, the CRSF FLIGHT_MODE telemetry frame
  (type `0x21`) that Betaflight already sends carries this directly as text,
  and — critically — **a trailing `*` means DISARMED, not armed**
  (`telemetry/crsf.c: crsfFrameFlightMode`, confirmed from source). Armed is
  the absence of the trailing `*`. Getting this backwards would silently
  disable the arm-lock, so `safety.lua` must implement it exactly this way,
  and Task testing must explicitly bench-verify both states.

## Data flow

1. On script open, `main.lua` queries `MSP_FC_VARIANT`/`MSP_API_VERSION` to
   confirm an ELRS+Betaflight link exists and firmware is compatible; shows an
   explicit "not connected" / "unsupported FC" state otherwise.
2. `safety.lua` polls arm status every cycle; while armed, all pages render
   read-only (values visible, controls disabled) with a persistent
   "ARMED — read only" banner.
3. Selecting a tab loads that page's relevant MSP GET messages into
   `state.lua` for the currently selected profile slot.
4. Editing a slider/field updates only the staged copy in `state.lua` (dirty
   flag set) — nothing is sent to the FC yet.
5. Pressing **Save** sends the corresponding SET messages, then
   `MSP_EEPROM_WRITE` to persist; **Cancel/Reload** discards staged edits and
   re-reads from the FC.
6. Switching profile slots (1/2/3) sends `MSP_SELECT_SETTING` (command id 210;
   value bit 7 set = rate profile index, clear = PID profile index — confirmed
   from source, and note this differs from an earlier draft's assumed id of
   10), re-reads that slot's values, and discards unsaved edits in the current
   slot (with a confirmation if dirty).

## PID sliders

Reads and writes Betaflight 4.5's native simplified-tuning slider fields
directly via `MSP_SIMPLIFIED_TUNING`/`MSP_SET_SIMPLIFIED_TUNING` — 8 raw U8
percentage values (master multiplier, roll/pitch ratio, I gain, D gain, PI
gain, D-min ratio, feedforward gain, pitch PI gain) plus a mode byte. The
firmware computes the resulting per-axis P/I/D/D-min/F itself; this script
does not replicate that math. A live preview of the resulting per-axis values
before saving is possible via `MSP_CALCULATE_SIMPLIFIED_PID` (id 142, computes
without persisting) but is not required for the MVP.

## Rates

All four rate types supported with a type selector; each type gets its own
slider set, converted through `MSP_RC_TUNING`/`MSP_SET_RC_TUNING`.

## Filters

Gyro LPF1/LPF2 and D-term LPF1/LPF2 cutoff frequencies only, via
`MSP_FILTER_CONFIG`/`MSP_SET_FILTER_CONFIG`.

## VTX

Power level, band, and channel via `MSP_VTX_CONFIG`/`MSP_SET_VTX_CONFIG`.

## Error handling

- MSP request timeout (no CRSF telemetry response within a threshold) — page
  shows "no response from FC" and disables Save until a successful re-read.
- Malformed/unexpected MSP response — discarded, treated as a timeout (never
  partially applied).
- Any write failure (no ACK) — Save reports failure explicitly; never assumes
  success.
- Arm-lock is fail-safe: if arm status can't be determined, the script treats
  the craft as armed (locks edits) rather than assuming disarmed.

## Testing

Bench-only validation (props off) — no in-flight testing of settings changes
is in scope:

1. **Transport layer** — unit-testable in isolation against a bench-connected
   FC before any UI work: confirm GET round-trips for every message type
   used.
2. **Per-page bench testing** — each page tested individually for correct
   read/display, staged-edit behavior, and Save/Cancel round-trips, verified
   against Betaflight Configurator's own values before/after.
3. **Arm-lock verification** — explicitly test that editing is blocked when
   armed, using a bench arm (props off, safe location).
