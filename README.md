# Betaflight Settings Dashboard for EdgeTX

An EdgeTX Tools LUA script for reading and writing Betaflight settings (PID
simplified-tuning sliders, rate profiles, gyro/D-term filters, VTX config,
throttle/motor settings) over MSP-over-CRSF telemetry, without needing a USB
connection to Betaflight Configurator.

Originally built for and verified on a Jumper T15 (EdgeTX 2.9+, 480x272
color touchscreen). The layout uses no hardcoded screen-size numbers and
sizes its chrome (footer, tab bar, arm-lock banner) from the radio's actual
`LCD_W`/`LCD_H`, so it also works on other EdgeTX color-screen radios of
480px width and 272px height or larger -- including RadioMaster's 480x320+
color radios -- confirmed compatible on real hardware. A touchscreen is used
for all editing, but its absence is handled gracefully: every touch-input
code path is nil-guarded, so on a non-touch radio the script still loads and
displays live FC data correctly; only editing values requires a touchscreen
for now.

## Requirements

- EdgeTX 2.9 or later, color LCD radio, 480px wide x 272px tall or larger
- ExpressLRS (CRSF) link with MSP-over-telemetry enabled
- Betaflight running MSP API 1.44 or later -- this covers Betaflight 4.5.3
  through the current calendar-versioned releases (e.g. 2026.6.1). The
  script checks `MSP_API_VERSION`, not the firmware version string, so it
  stays compatible with future Betaflight releases as long as they don't
  remove or reorder the MSP fields this project depends on.
- A touchscreen, to edit values (the script runs and displays data without
  one, but editing is touch-only for now)

## Pages / Tabs

- **PIDs** -- the 8 "PID Tuning Sliders" (Damping, Tracking, Stick Response,
  Dynamic Damping, Drift/Wobble, Pitch Damping, Pitch Tracking, Master
  Multiplier), labeled/ordered to match Betaflight Configurator exactly.
  Split layout: sliders on the left, a live per-axis P/I/D/D-Min/FF preview
  on the right (via `MSP_CALCULATE_SIMPLIFIED_PID`, computed by the FC
  without saving anything).
- **Rates** -- all 4 rate types (Betaflight/RaceFlight/KISS/Actual/
  QuickRates), Roll/Pitch/Yaw x Sensitivity/Max Rate/Expo grid, with the
  same per-type display scaling Configurator uses.
- **Filters** -- single-column list covering Gyro/D-Term Lowpass 1 & 2 (with
  filter type), Gyro RPM Filter, and Dynamic Notch Filter, all as plain
  always-visible fields -- no on/off switches. Dialing a filter's cutoff/
  count/harmonics field down to 0 is what disables it on the FC itself
  (Betaflight's own convention), so there's nothing separate to toggle.
  D-Term Lowpass 1 also has a STATIC/DYNAMIC mode row, matching
  Configurator's own behavior (there's no separate "mode" byte in the
  firmware -- it's inferred from whether the dynamic-min field is non-zero,
  the same way Configurator infers it). Gyro/D-Term Notch and Yaw Lowpass
  were dropped from this tab to cut clutter and give the remaining fields
  more room -- their values are left untouched on the FC, not reset.
- **VTX** -- Band, Channel, Power.
- **Motor** -- Throttle Boost, Motor Output Limit, Dynamic Idle Value, Vbat
  Sag Compensation %, Thrust Linearization % -- all plain fields, 0 = off for
  the last two.

## Editing

- Tap a row (label or value -- the whole row is one tap target) to focus it,
  then turn the radio's jog dial to adjust; tap again to confirm/unfocus.
- Nothing is written to the flight controller until you press **Save**;
  editing only stages the change locally. **Save** writes every dirty page's
  changes and commits them to EEPROM in one flow; a green "Saved!"
  confirmation shows in the footer for a couple seconds once that's
  confirmed. **Cancel** discards unsaved edits.
- Editing is blocked outright while the flight controller reports ARMED.

## Safety / connection behavior

- Arm status is read from EdgeTX's own decoded "FM" telemetry sensor
  (Betaflight's CRSF FLIGHT_MODE frame), not guessed from anything this
  script sends itself. Unknown/stale telemetry always fails safe to ARMED
  (locked), never the other way around -- including the one genuinely
  ambiguous case, the fixed "!FS!" failsafe-mode text, which Betaflight
  sends with no arm/disarm suffix at all.
- If the flight controller's telemetry goes stale for more than ~1.5s while
  connected (unplugged, swapped for a different craft, powered off), the
  whole app resets itself back to its just-launched state -- cached
  settings, dirty edits, and any in-flight save/profile-switch are all
  dropped -- and it automatically retries the connection handshake. A
  different flight controller can be plugged in without restarting the
  script.
- This tool has only been bench-tested (props off). No in-flight testing of
  settings changes has been performed.

## Known limitations

- The Filters tab always shows every field (no collapsing), since D-Term
  Lowpass 1's STATIC/DYNAMIC row is the one case where a field's meaning
  genuinely depends on another field's value; everything else is just a
  plain row.
- Non-touch navigation (jog-dial-only, no tap-to-focus) isn't implemented --
  EdgeTX doesn't expose a portable "confirm" key to Lua scripts across all
  supported radios, so a touchscreen is currently required to select which
  field the dial edits.
- Saving a change back to the FC and confirming it survives a power cycle
  has not yet been end-to-end verified by a project maintainer on hardware.

## Installation

Copy the contents of `src/SCRIPTS/` from this repo to the `/SCRIPTS/` folder
on your radio's SD card, so you end up with:

```
/SCRIPTS/TOOLS/BFDash/main.lua
/SCRIPTS/TOOLS/BFDash/...
```

Launch it from the radio's Tools menu (long-press SYS or the model's Tools
shortcut, depending on radio layout).

## Development

Run the pure-Lua test suite (transport, codec, and state logic — no radio
hardware required):

```bash
lua tests/run_all.lua
```

UI and radio-link behavior (`main.lua`, `pages/*.lua`) can only be verified on
the physical radio bench-connected to a flight controller — see the plan in
`docs/superpowers/plans/2026-09-09-betaflight-settings-dashboard.md` for the
bench-test checklist per page.

Every MSP wire-format assumption in this codebase is verified directly
against Betaflight firmware source (`src/main/msp/msp.c` and related headers)
at the relevant tag, and against betaflight-configurator's own source for UI
terminology and enable/mode logic -- never guessed. When extending a page,
follow that same pattern: fetch the actual source for the MSP command(s)
involved before writing byte offsets.
