# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub's **Security advisories**
page rather than a public issue. Include reproduction steps, affected macOS and
hardware versions, and the expected impact.

## Security boundaries

MacDisplaySync does not use the network or require administrator privileges. It
does use private macOS display APIs and can send raw DDC/CI commands to connected
monitors. Raw commands may change undocumented hardware state; they are intentionally
kept in the Advanced section.

The local app is ad-hoc signed. Public releases should be Developer ID signed and
notarized before being presented as trusted downloadable binaries.
