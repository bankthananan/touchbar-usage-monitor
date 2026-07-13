# Contributing

Thanks for helping improve Touch Bar Usage Monitor.

## Before opening an issue

- Confirm the Mac has a physical Touch Bar and runs macOS 12 or later.
- Run the affected provider CLI directly and confirm it is signed in.
- Check the `TB` menu-bar item for the complete provider error.
- Search existing issues before creating a new one.

Never include OAuth tokens, Keychain contents, CLI credential files, or unsanitized debug output in an issue.

## Development workflow

1. Fork and clone the repository.
2. Create a focused branch from `main`.
3. Make the smallest change that solves the problem.
4. Run the local checks:

   ```sh
   make clean
   make all
   plutil -lint Resources/Info.plist Resources/com.local.touchbar-usage-monitor.plist
   zsh -n Scripts/install.sh Scripts/uninstall.sh
   ```

5. If a provider parser changes, add or update a sanitized fixture in `Tests/parser_tests.m`.
6. Open a pull request describing the behavior change, macOS version, and how it was verified.

`make smoke` contacts live provider services through the installed CLIs. It is optional and must never be used in automated public CI with personal credentials.

## Code guidelines

- Keep the app dependency-free and compatible with the minimum macOS version in `Resources/Info.plist`.
- Preserve provider isolation: one provider failure must not stop the other cards.
- Never log access tokens, Keychain payloads, or authorization headers.
- Treat provider output and HTTP responses as untrusted input.
- Document any additional private macOS API use prominently.
