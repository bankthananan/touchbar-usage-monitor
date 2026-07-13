# Security Policy

## Supported version

Security fixes are applied to the latest commit on `main`. This is a local utility and does not have a hosted service.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository. Do not open a public issue if a report contains credential-handling details or a reproducible way to expose local secrets.

Include the affected macOS version, provider, impact, and minimal reproduction steps. Remove all tokens, authorization headers, Keychain values, account identifiers, and private CLI output before submitting.

## Credential model

- Claude credentials are requested from macOS Keychain at runtime and kept in memory only.
- Codex and Antigravity authentication remains inside their respective CLIs.
- The app does not persist provider tokens or send them to any project-owned service.

Because the app uses an undocumented AppKit Touch Bar selector, macOS updates may affect availability. That compatibility risk is separate from credential security.
