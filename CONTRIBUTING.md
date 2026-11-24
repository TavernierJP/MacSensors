# Contributing to MacSensors

Issues and pull requests in French or English are welcome.

## Report a problem

Include the Mac model/chip, macOS version, MacSensors version, what you expected and what happened. For missing or suspicious sensors, include the key/name and whether the raw-channel option was enabled. Share a minimal, reviewed excerpt of `--sensors` output if useful. Remove personal information from screenshots and logs; serial numbers and Apple account details are not needed.

## Develop

Use an Apple Silicon Mac, Apple's Command Line Tools/macOS SDK and Python 3. No third-party packages are required.

```sh
python3 scripts/build.py
python3 scripts/test.py
python3 scripts/package.py
```

Build before running tests: the tests link the bridge object produced by the build. Also test the actual menu bar interaction, sleep/wake, missing-sensor behavior and preferences on your Mac when changing those behaviors. Automated tests do not prove a sensor's physical meaning.

## Temperature mappings

Do not infer a physical sensor from a key beginning with `T`, a plausible numeric value, or one matching another app. Document the source, model, macOS version and any controlled observations. Conflicting or unsupported mappings should remain raw/unidentified. Do not equate software channel count with physical probe count or claim per-core locations without evidence.

The project reads hardware state only. Keep writes to SMC, fan control, administrator helpers and remote services outside the scope of routine sensor fixes.

## Pull requests

- Keep the change focused and explain the user-visible result.
- Run the applicable build/tests and report any physical hardware checks separately.
- Update documentation when behavior, platform support or sensor interpretation changes.
- Include an appropriate regression check for a behavior bug; documentation edits do not need tests.
- Do not commit `.build`, app bundles, credentials or unrelated personal files.

Contributions are distributed under the project's MIT License. Only contribute work you have the right to share under that license.
