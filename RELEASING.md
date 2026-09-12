# Releasing MacDisplaySync

## Prepare

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Move completed entries from `Unreleased` into a dated version in
   `CHANGELOG.md`.
3. Run `make clean && make package` on an Apple Silicon Mac.
4. Confirm the app bundle contains arm64 executables and that `make check` passes.

The versioned ZIP is written to `dist/`. That directory is intentionally ignored
by Git.

## Signing and distribution

Local and CI builds are ad-hoc signed. Before advertising a binary as a trusted
download, sign it with a Developer ID Application certificate and submit it to
Apple's notarization service. Re-run signature validation after stapling the
notarization ticket.

Create a signed Git tag matching the app version, push it, and attach the verified
ZIP to a GitHub Release. Include the relevant `CHANGELOG.md` section and note the
supported macOS, Mac architecture, connection type, and any monitor-specific
limitations.
