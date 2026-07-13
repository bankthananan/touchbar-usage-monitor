# Touch Bar Usage Monitor

A small native macOS utility that puts Claude Code, Antigravity, and Codex quota usage on the physical Touch Bar whenever Warp is frontmost.

Each card shows the percentage **used** for the provider's 5-hour and 7-day/weekly windows, plus the time remaining until reset. A dash means the provider did not return that window.

> [!IMPORTANT]
> This project uses an undocumented AppKit system-modal Touch Bar API. It is intended for personal, local installation and cannot be distributed through the Mac App Store. A future macOS update could break this behavior.

## Requirements

- A MacBook Pro with a physical Touch Bar.
- macOS 12 or later.
- Apple Command Line Tools (`xcode-select --install`).
- [Warp](https://www.warp.dev/) Stable, Preview, or the standard Warp build.
- At least one supported provider CLI, authenticated for the current macOS user:
  - Claude Code (`claude`)
  - Antigravity (`agy`)
  - Codex (`codex`)

Missing or unauthenticated providers report an error in the menu-bar status and do not prevent the others from working.

## Install

```sh
git clone https://github.com/bankthananan/touchbar-usage-monitor.git
cd touchbar-usage-monitor
make test
make install
```

`make install` builds an ad-hoc-signed app, copies it to `~/Applications`, and installs a per-user LaunchAgent so it starts at login. No administrator access is required.

### Provider setup

1. Sign in to each provider CLI you want to monitor.
2. For Antigravity, trust the cloned project directory once:

   ```sh
   cd /path/to/touchbar-usage-monitor
   agy
   ```

   Choose **Yes, I trust this folder**, then exit. The installer configures the monitor to use this directory and never accepts the trust prompt for you.

3. On the first Claude refresh, macOS may ask whether Touch Bar Usage Monitor can read the `Claude Code-credentials` Keychain item. Choose **Always Allow** for automatic updates.

## Use

- Focus Warp to show the three quota cards on the Touch Bar.
- Switch away from Warp to restore the next app's Touch Bar.
- Tap a provider card or the refresh icon to update immediately.
- Open the `TB` menu-bar item to see provider errors or choose **Refresh now**.

Refresh intervals are one minute for Claude and Codex, and five minutes for Antigravity. Reset countdowns update whenever fresh provider data arrives.

## What the app reads

| Provider | Local integration | Network behavior |
| --- | --- | --- |
| Claude | Reads the existing Claude Code OAuth record from Keychain with Security.framework. | Calls Anthropic's usage endpoint with the in-memory token. |
| Codex | Starts `codex app-server --stdio` and requests `account/rateLimits/read`. | The Codex CLI handles its normal account connection. |
| Antigravity | Opens `agy` in a local pseudo-terminal, runs `/usage`, parses the Claude/GPT group, then exits. | The Antigravity CLI handles its normal account connection. |

Tokens are never logged or written into this repository. Antigravity reports percentage remaining; the app converts it to percentage used so every card is consistent.

Provider response formats are not controlled by this project. If a provider returns only one quota window, the other field remains `—`.

## Build and test

```sh
make test       # parser unit tests
make build      # app bundle at build/TouchBarUsageMonitor.app
make all        # test, then build
make smoke      # live provider checks; requires signed-in CLIs
make clean
```

The project uses Objective-C, AppKit, Foundation, and Security.framework. It has no third-party build dependencies.

## Uninstall

```sh
make uninstall
```

This removes the app from `~/Applications` and unloads/removes its per-user LaunchAgent. It does not change provider credentials or CLI configuration.

## Contributing and security

Bug reports and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change. For credential-handling concerns, follow [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
