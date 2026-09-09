# EdgeTX Betaflight Settings Dashboard (LUA Tools Script)

Date: 2026-09-09

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
transport/msp.lua       - MSP-over-CRSF framing (crossfireTelemetryPush/Pop),
                           chunking, sequence numbers, CRC, request/response
                           matching, timeouts
transport/mspMsgs.lua   - encode/decode for specific MSP messages: PID,
                           RC_TUNING, FILTER_CONFIG, VTX_CONFIG, profile
                           select, EEPROM_WRITE, FC_VARIANT/VERSION,
                           API_VERSION
state.lua               - in-memory model: last-read FC values, staged
                           (unsaved) edits, dirty flag, selected PID/rate
                           profile slot
safety.lua              - arm-status polling (CRSF flight-mode telemetry
                           sensor, MSP_STATUS fallback), drives read-only lock
pidSliders.lua          - Betaflight 4.5 master-slider math (Master P/I/D,
                           Roll/Pitch ratio, Response, Damping, Stability, FF
                           sliders -> per-axis P/I/D/FF)
pages/pids.lua           - PID slider screen
pages/rates.lua          - rate screen (rate-type selector)
pages/filters.lua        - gyro/D-term lowpass cutoff screen
pages/vtx.lua            - VTX power/band/channel screen
```

Each page module exposes `create()`, `update(staged)`, `event(...)` and reads
/writes only through `state.lua` — pages never touch the MSP layer directly.
This keeps the risky wire-protocol code in one place, testable independently
of UI.

The MSP-over-CRSF transport layer is based on the proven framing pattern used
by established open-source EdgeTX/Betaflight LUA projects (e.g.
`betaflight-tx-lua-scripts`, `rfsuite`) rather than re-derived from the raw
spec — chunking/CRC/sequencing bugs there would silently corrupt writes to the
flight controller, so this is not an area to improvise in.

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
6. Switching profile slots (1/2/3) sends the MSP profile-select command,
   re-reads that slot's values, and discards unsaved edits in the current slot
   (with a confirmation if dirty).

## PID sliders

Implements Betaflight 4.5's actual master-slider formula (Master P/I/D,
Roll/Pitch ratio, Response, Damping, Stability, separate Roll/Pitch/Yaw FF) in
`pidSliders.lua`, converting to/from the raw per-axis P/I/D/FF values that
`MSP_SET_PID` transmits. Pinned to the 4.5.x formula as implemented in
Betaflight firmware source (not documented on the wiki) and isolated so a
future BF version bump only requires swapping this one file.

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
