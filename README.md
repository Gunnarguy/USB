# USB

A SwiftUI app that inspects USB, Thunderbolt and storage devices on a Mac.

## Platforms

macOS 26.0 or later. The project also targets iPhone and iPad, where the app shows only an information screen, because inspection uses macOS system APIs.

## What the macOS app reads

- USB devices, their descriptors, speed and bus power, through IOKit
- USB host controllers
- Thunderbolt ports and switches
- Storage volumes, tracked through Disk Arbitration, with read and write byte counts, errors and retries

## Status

Prototype, not maintained. Last commit: May 13, 2026.

No license file is included.
