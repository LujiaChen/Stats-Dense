# Architecture and validation

## Fixed five-metric presentation

Dense is intentionally specialized. It has three utilization groups above a temperature/power pair. It is not a renderer for arbitrary module widgets. `DenseCombinedView.moduleNames` identifies CPU, GPU, RAM, and Sensors; `CombinedView` retains other enabled widgets beside this dashboard.

`CombinedValues` carries optional utilization, temperature, power, and sensor names. Existing module callbacks publish distinct snapshots on the main thread. Dense formats these values, caches CoreText lines and widths, and redraws when displayed strings change. There is no new reader or polling timer.

The status item's allocation is established during layout, not during sample delivery. On the tested Mac, content is 90 pt and the native status-item window is 106 pt. Ordinary two-digit samples have approximately 3.94 pt between groups, with zero explicit outer padding. The number height remains 13.5 pt. If a row containing 100% readings needs more room, value glyphs are fitted horizontally in the same allocation; labels and the physical readings retain their dimensions. No reading or percent sign is hidden.

## Data sources

| Field | Existing source |
| --- | --- |
| CPU | Total CPU utilization |
| GPU | Utilization from the GPU selected by the existing module |
| RAM | Memory usage ratio |
| Temperature | Enabled temperature sensor in existing stack order, then Average CPU, then available temperature |
| Power | Sensors' System Total / `PSTR` sample |

Unavailable values remain placeholders. Disabling a provider does not select another metric. Normal widget configuration does not remap these five fields.

## Popup and window behavior

On macOS 26+, Combined content is hosted by `NSPopover`, allowing AppKit to supply its native material. The inherited opaque foreground is removed from that path. On older systems the existing popup path is retained. The result is an official public-API material, not a claim to duplicate every rendering detail of Apple's Weather app.

The main settings window is constructed with normal Space semantics, then the app immediately restores its menu-bar activation policy. This is separate from the status item's popup.

## Validation boundaries

Local presentation tests passed (11 cases); the separate live hardware test verified updates from all five providers and opening/closing Combined popups in Normal, Dense, and Icon Only modes. Light/Dark text and glyph-bound checks include simultaneous 100% readings. These results were obtained on an Apple M5 MacBook Air, macOS 27.3, Xcode 27.0. Not every Mac or stable macOS version has been tested.

Earlier experimental width animation caused repeated native menu bar layout and snapshot work. Both automatic resizing and its animation timer have been removed. This architectural change is not a quantified battery-life guarantee; sensor reading and native material composition still have costs.

## Keeping the fork current

The starting point is Stats v3.0.25 (`27fa75a53d57072ec06adc730dcfe67633d639d2`). The likely merge points are CombinedView's layout/click routing, AppSettings' Combined controls, the MenuBar snapshot interface, module callback hooks, and the Dense-only update-check guard. Keep the original license and credit when updating.

The Dense bundle never silently installs upstream Stats over itself. Manual checks open this fork's release page. Other bundle identities retain upstream behavior.
