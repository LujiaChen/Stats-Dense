# Changelog

## v3.0.25-dense.1 — Preview 1

Based on Stats v3.0.25.

- Add a focused two-row Dense mode for CPU, GPU, RAM, temperature, and system power.
- Keep a fixed menu bar allocation with compact label/value groups and tabular digits.
- Reuse existing module samples and cache text layout; remove automatic width changes and the width-animation timer.
- Use the native Combined popover material on macOS 26+, with the existing older-system popup path retained.
- Preserve Normal Combined, Icon Only, extra horizontal modules, and the settings-window Space-lifecycle correction.
- Distribute Dense with its own bundle identity and manual updates, preventing silent replacement with upstream Stats.
- Add English build instructions, explicit scope/availability limits, contribution forms, and a local preview build helper.

Dense slots are fixed in this preview. The local package is ad-hoc signed, not notarized, and omits the optional desktop WidgetKit extension. Hardware behavior has been validated on the documented M5 test Mac, not every supported Mac.
