# Architecture

MacDisplaySync is intentionally small and dependency-free. The app bundle contains
three arm64 executables:

```text
MacDisplaySync.app
└── Contents
    ├── MacOS/MacDisplaySync       SwiftUI menu-bar app
    └── Resources
        ├── monitor-ddc            Objective-C DDC/CI helper
        └── monitor-sensor         Read-only built-in display probe
```

## UI and state

`MacDisplaySyncApp.swift` defines the `MenuBarExtra` UI. `MonitorStore.swift` owns
display discovery, feature readings, serialized writes, persistence, and follow-mode
timers. The UI only renders controls whose VCP probes return valid responses.

## DDC transport

`monitor-ddc` maps CoreGraphics displays to their `DCPAVServiceProxy` and uses
Apple Silicon's private `IOAVService` I2C functions. It supports:

- `list` for DDC-capable external displays
- `read` and `write` for arbitrary VCP codes
- `scan` for a read-only pass over all 256 VCP codes

DDC operations are serialized. LG firmware requires repeated packets for reliable
read and write behavior, so the helper sends idempotent requests twice.

## Sensor following

`SensorSupport.swift` reads the active built-in display's current brightness through
DisplayServices. This is the value after macOS automatic-brightness adjustment. A
sample is rejected when the built-in display is absent, inactive, or asleep, which
also covers lid-closed operation.

Night Shift state is read from CoreBrightness. The LG's color preset is changed to
5000 K while Night Shift is warm and the user's previous preset is restored when
warmth following is disabled or Night Shift returns to neutral.

## Private API policy

Private symbols are resolved at runtime or linked only in the local helper. Missing
sensor symbols degrade to an unavailable control instead of crashing the app. A
future macOS version may still require transport updates.
