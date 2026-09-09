# Betaflight Settings Dashboard for EdgeTX

An EdgeTX Tools LUA script for reading and writing Betaflight 4.5.x settings
(PID simplified-tuning sliders, rate profiles, gyro/D-term filter cutoffs,
VTX config) over MSP-over-CRSF telemetry, without needing a USB connection to
Betaflight Configurator.

Originally built for and verified on a Jumper T15 (EdgeTX 2.9+, 480x272
color touchscreen). The layout uses no hardcoded screen-size numbers and
sizes its chrome (footer, tab bar, arm-lock banner) from the radio's actual
`LCD_W`/`LCD_H`, so it should also work on other EdgeTX color-screen radios
of 480px width and 272px height or larger -- including RadioMaster's
480x320+ color radios -- without any changes, though those haven't been
hardware-tested by this project yet. A touchscreen is used for all editing,
but its absence is handled gracefully: every touch-input code path is nil-
guarded, so on a non-touch radio the script still loads and displays live
FC data correctly; only editing values requires a touchscreen for now.

## Requirements

- EdgeTX 2.9 or later, color LCD radio, 480px wide x 272px tall or larger
- ExpressLRS (CRSF) link with MSP-over-telemetry enabled
- Betaflight 4.5.x flight controller firmware
- A touchscreen, to edit values (the script runs and displays data without
  one, but editing is touch-only for now)

## Installation

Copy the contents of `src/SCRIPTS/` from this repo to the `/SCRIPTS/` folder
on your radio's SD card, so you end up with:

```
/SCRIPTS/TOOLS/BFDash/main.lua
/SCRIPTS/TOOLS/BFDash/...
```

Launch it from the radio's Tools menu (long-press SYS or the model's Tools
shortcut, depending on radio layout).

## Safety

- The script blocks all edits while the flight controller reports ARMED.
- Nothing is written to the flight controller until you press **Save**;
  editing a slider only stages the change locally.
- **Save** writes the change and commits it to EEPROM. **Cancel** discards
  unsaved edits.
- This tool has only been bench-tested (props off). No in-flight testing of
  settings changes has been performed.

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
