# Contributing

Thanks for helping improve MacDisplaySync.

## Before opening a change

- Search existing issues and describe the monitor, Mac model, macOS version,
  connection type, and whether DDC/CI is enabled in the monitor OSD.
- Keep the app local-only. Do not add analytics, telemetry, accounts, or required
  network services.
- Do not add a monitor control to the normal UI solely because a VCP code returned
  data. Confirm that the feature is writable and document its value semantics.
- Treat power, reset, input switching, and raw VCP writes as potentially disruptive.

## Build and check

```sh
make check
```

The automated check is read-only. If a change affects hardware writes, test against
real hardware by recording the original value, changing it by the smallest possible
amount, reading it back, and restoring it immediately.

## Pull requests

Keep pull requests focused. Include:

1. What changed and why.
2. Hardware and macOS versions used for testing.
3. Read/write/restore evidence for DDC changes.
4. Screenshots for visible UI changes.

By contributing, you agree that your contribution is licensed under the MIT License.
