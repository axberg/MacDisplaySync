# MacDisplaySync

A small, native macOS menu-bar controller for DDC/CI displays on Apple Silicon.
It changes the monitor's hardware settings rather than applying a dimming overlay.

MacDisplaySync is local-first: it has no accounts, analytics, update service, or
network access. The app is currently distributed as an ad-hoc-signed local build.

## Controls

- Brightness, contrast, and sharpness
- Volume, mute, bass, treble, and balance
- Input source and LG's alternate input command
- Picture-by-Picture modes and the monitor OSD language
- Color temperature, RGB gain, hue, and saturation
- Horizontal and vertical positioning
- Display power and factory reset (with confirmation)
- Raw VCP read/write for vendor-specific MCCS commands
- A full 256-code VCP Explorer for discovering every readable monitor feature
- Opt-in brightness sync from the MacBook's sensor-adjusted built-in panel
- Opt-in Night Shift warmth sync that restores the previous monitor color preset

The panel probes each readable VCP feature and only presents controls that the
connected monitor reports as supported.

Follow mode pauses without writing whenever the built-in display is inactive or
asleep, including when the MacBook lid is closed. It resumes when the built-in
display comes back on.

Brightness is sampled every two seconds and only writes when the rounded hardware
level changes. Color warmth follows Night Shift's live state using the monitor's
5000 K preset, then restores the preset that was active when follow mode was enabled.

## Build and install

Xcode Command Line Tools or a full Xcode installation is required.

```sh
make build
make install
```

The build produces `build/MacDisplaySync.app`. The install script copies it to
`/Applications` and opens it. No network access, analytics, or elevated privileges
are used.

```sh
git clone https://github.com/axberg/MacDisplaySync.git
cd MacDisplaySync
make install
```

## Compatibility

- Apple Silicon Mac
- macOS 13 or newer
- Direct USB-C / DisplayPort connection with DDC/CI enabled on the monitor

DisplayLink and some HDMI adapters do not pass DDC/CI commands. The low-level
helper uses private macOS `IOAVService` APIs, so a future macOS release may require
an update.

MacDisplaySync is not suitable for the Mac App Store because generic DDC access,
built-in display brightness, and Night Shift state rely on private macOS APIs.

## Development

```sh
make check      # compile, validate signing/plist, and run read-only probes
make package    # create a versioned ZIP in dist/
make clean
```

The checks never write monitor settings. Hardware writes should be tested by moving
a value by one step, reading it back, and restoring the original value immediately.
See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Safety

- Power-off and factory reset require confirmation.
- Unsupported features are hidden from the normal interface.
- Advanced raw VCP writes can change undocumented monitor state; use them carefully.
- Follow mode stops issuing writes when the built-in display is inactive or asleep.

## Attribution

The Apple Silicon DDC transport is derived from the MIT-licensed `m1ddc` project
by waydabber. See `THIRD_PARTY_LICENSES.md`.

## License

MacDisplaySync is available under the [MIT License](LICENSE).
