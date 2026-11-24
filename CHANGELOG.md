# Changelog

## 1.2 — 2026-11-23

- Hide unidentified SMC channels by default; the advanced view marks them as raw, without a Celsius unit or Fahrenheit conversion.
- Prefer `TCMb` and `TCMz` for automatic CPU selection and exclude raw channels from summaries.
- Remove conflicting `Tf` CPU/GPU labels. Describe identified M3 CPU/GPU keys as zones rather than physical cores.
- Preserve unavailable selected readings as placeholders.
- Add regression checks for raw constants and misleading high numeric values; 46 checks in total.

### Open-source publication — 2026-11-24

- Add the MIT License, English/French documentation, contribution guide and issue templates.
- Add an Apple Silicon macOS build/test/package workflow.
- Include the complete repository source and license in distribution archives.
- App runtime sources remain the same as the delivered 1.2 build.

## 1.1 — 2026-11-21

- Add selectable SMC/HID temperature readings to the CPU/RAM utility.
- Rename the app to MacSensors and add the `designed by TavernierJP` About window.

The permissive temperature enumeration in 1.1 is superseded by the conservative filtering in 1.2. A numeric SMC key is not sufficient evidence of a physical temperature reading.
