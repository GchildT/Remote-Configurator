# Betaflight Settings Dashboard for EdgeTX

An EdgeTX Tools LUA script for reading and writing Betaflight 4.5.x settings
(PID simplified-tuning sliders, rate profiles, gyro/D-term filter cutoffs,
VTX config) over MSP-over-CRSF telemetry, without needing a USB connection to
Betaflight Configurator.

Built for a Jumper T15 (EdgeTX 2.9+, color LCD) linked via ExpressLRS.

## Requirements

- EdgeTX 2.9 or later, color LCD radio
- ExpressLRS (CRSF) link with MSP-over-telemetry enabled
- Betaflight 4.5.x flight controller firmware

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
