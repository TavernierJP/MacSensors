# MacSensors 1.2 validation

Last local verification: 2026-11-24. Target: arm64, macOS 13 or later.

## Automated checks

- Compile the Swift/AppKit app and C IOKit bridge with Apple's tools.
- Check the 80-byte SMC message structure and payload offset at compile time.
- Ad hoc sign the app and verify the bundle with `codesign --verify --strict`.
- Run 46 checks covering CPU/RAM calculations and real host CPU/RAM sampling; SMC fixed-point/float decoding; invalid data; sensor classification; summaries; automatic/multiple selection; and missing channels.
- Reproduce unidentified values such as `Tf06 = 83.7` and `Tf0C = 1`: hidden in normal mode, raw in advanced mode, no Fahrenheit conversion and excluded from CPU summaries.
- Render and inspect the measurement panel and About view in light/dark modes, without invented thermal readings.
- Package the app and the complete source/license/documentation archives.

## Hardware evidence and limits

Development host: M3 Max MacBook Pro, 14 CPU cores, 36 GiB RAM, macOS 27.0.1. CPU/RAM sampling works in the restricted development environment. SMC access there returns `0xe00002e2` and no HID temperature services are accessible, so thermal decoding/selection tests use controlled inputs rather than physical sensor measurements.

A user screenshot from version 1.1 demonstrates that the app can run graphically and read SMC channels in a normal Mac session. It does not establish the physical meaning of every channel, nor validate the updated version 1.2 mapping.

The version 1.2 menu interactions, launch at login and live temperature mappings still need physical-machine testing. Automated GUI launch is blocked by LaunchServices in the development environment; offscreen interface rendering succeeds. Virtual CI runners cannot substitute for physical thermal validation.

Available channels vary by hardware, firmware and macOS. Community key catalogs sometimes disagree. Unidentified keys remain raw. A software channel count must not be presented as a physical probe count. See [REFERENCES.md](REFERENCES.md).

## Performance and distribution

The app uses one process, cached sensor connections/catalogs, a serial thermal queue, limited polling and sleep suspension. Overall graphical-session resource use has not been benchmarked. Missing memory-pressure/swap access is shown as unavailable rather than zero.

The ZIP contains an arm64 app with a local ad hoc signature. It has no Developer ID certificate or Apple notarization. The optional DMG path requires host disk-image services and has not been validated in the restricted environment.
