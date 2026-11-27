# RSS Reader

rssreader is a SwiftUI app for iPhone, iPad, and macOS that connects to FreshRSS and presents your feed items with a two-pane reading workflow, inline content viewing, and read/unread management actions.

Unread articles scrolled past the top of the feed are marked with a grey ring
instead of the unread dot. They remain
unread until opened or explicitly marked read, including with Mark All as Read.
Skipped labels are stored per FreshRSS account and sync between devices through the
app's private CloudKit database when iCloud is available. Local labels remain available
when CloudKit is unavailable and are reconciled on the next successful sync.

To run the native macOS feed-scrolling regression checks:

```sh
swiftc -parse-as-library rssreader/UI/Feed/FeedSkipTracking.swift tests/FeedScrollChecks.swift -o /tmp/feed-scroll-checks
/tmp/feed-scroll-checks
```

The checks briefly open a test window and exercise scrolling in a real SwiftUI
list, including partial visibility, reverse scrolling, filtering, and fast jumps.

On devices with Apple Intelligence available, AI Summary summarizes the article
shown in the in-app Web view using Apple's on-device model. Summaries are cached
in memory while the detail view is open and regenerated if the page content
changes. When articles are set to open in an external browser, select Open in
App in AI Summary to load the page in the app first. Summaries may contain
mistakes.

To run the standalone macOS article-summary checks, compile and run:

```sh
swiftc -parse-as-library rssreader/UI/Detail/ArticleSummaryText.swift rssreader/UI/Detail/ArticleSummaryController.swift rssreader/UI/Web/WebView.swift rssreader/Core/EmbeddedWebNavigationPolicy.swift tests/ArticleSummaryChecks.swift -o /tmp/article-summary-checks
/tmp/article-summary-checks --real-model
```

The on-device model check is optional; omit `--real-model` to run the other
checks. Model-dependent checks are skipped when Apple Intelligence is unavailable.

## Karakeep

In Settings > Karakeep, enter your server's base URL and an API key created in
Karakeep Settings > API Keys, then select Save. The API key is stored in
Keychain; the server URL is stored locally.

Use Save to Karakeep in article actions (More Actions on iPhone) or an article's
context menu to save its original URL and title. A dismissible toast shows saving
progress, confirms new or existing bookmarks, and displays errors. Open in
Karakeep opens the native app's main screen when installed, avoiding article
deep links that lack back navigation. Otherwise, it opens the saved bookmark in
your browser. The native app must be connected to the same Karakeep account.
Saving does not change the article's read status. Disconnect removes the stored
connection and API key.

## Make targets

Run `make` or `make help` to list the available commands:

| Command | Action |
| --- | --- |
| `make install` | Install macOS first, then iPhone, attempting both even if either fails |
| `make dev` | Watch edits, rebuild, and relaunch in the configured simulator |
| `make install-mac` | Archive and install the Release macOS app |
| `make install-iphone` | Build, install, and launch on the configured iPhone |
| `make install-simulator SIMULATOR_ID=<UDID>` | Build, install, and launch on a specific simulator |
| `make slim-simulator SIMULATOR_ID=<UDID>` | Install in Simulator with opt-in simslim slimming |
| `make simulators` | List available simulators and their identifiers |
| `make devices` | List devices and their identifiers |
| `make build-mac` | Build Debug for macOS without signing or installing |
| `make build-ios` | Build Debug for iOS Simulator without installing |
| `make check` | Check installer shell syntax and patch whitespace |
| `make test` | Run all standalone macOS checks |
| `make test-feed` | Run native feed-scrolling checks |
| `make test-skipped` | Run skipped-item persistence checks |
| `make test-summary` | Run article-summary checks without real-model generation |
| `make test-karakeep` | Run Karakeep request and response checks |
| `make test-dev` | Run simulator watcher checks |

`make install` exits unsuccessfully if either installation fails.

Test executables are cached in `build/checks` and rebuilt when their sources
change. Feed checks briefly open a test window. Summary checks skip
model-dependent cases when Apple Intelligence is unavailable.

## Install on macOS

From the repository root:

```sh
make install-mac
```

The script archives the Release app and installs it into `/Applications`.
Run `./scripts/install_mac.sh --help` for configuration and destination options.

## Local configuration

Both device installers use the same ignored `.env` file:

```sh
cp .env.example .env
```

Set `DEVICE_ID` from `make devices` and `SIMULATOR_ID` from `make simulators`.
Leave an unused target empty. Use unquoted assignments and optional comments;
the file is parsed as data, never executed. Command-line values override it.
Do not overwrite an existing `.env` when switching targets.

## Install on an iPhone

From the repository root:

```sh
make devices
```

Set `DEVICE_ID=<identifier>` in `.env` using the phone's Identifier from
the device list, without quotes. The file is ignored by Git and is read as data,
not executed as shell code.

```sh
make install-iphone
```

The script builds, installs, and launches the Debug app. The phone must be paired
and trusted, unlocked, and have Developer Mode enabled. Xcode must have valid
signing credentials and provisioning for the device. USB and Xcode-paired
wireless devices are supported. Build products go into `build/iphone`.

## Install in Simulator

No signing credentials, physical device, or installation into `/Applications`
is needed. Pick an available iPhone or iPad simulator:

```sh
make simulators
make install-simulator SIMULATOR_ID=<UDID>
```

The installer uses ad-hoc signing so iCloud/KVS entitlements remain available;
an entirely unsigned simulator build would crash during service initialization.

Remember your development simulator with `SIMULATOR_ID=<UDID>` in `.env`.
Command-line `SIMULATOR_ID` overrides it.
You can then use `make install-simulator` without specifying a device.

For the continuous development loop:

```sh
make dev
```

It deploys immediately, then watches app sources, resources, shared Xcode
configuration, installer changes, and `.env`. After one second of
quiet following edits, it incrementally rebuilds and relaunches the app.
Builds run serially; changes made during a build trigger another build afterward.
Failures are shown in the terminal and `build/dev-simulator.log`; the watcher
waits for another edit rather than repeatedly retrying a broken build. A failed
build does not replace the last installed app. Ctrl-C stops watching.

The watcher needs Python 3 and no additional packages. It does not rerun simslim
on every edit; slimming already applied to the selected simulator persists.
Avoid running a second simulator build on this checkout while it is watching.
Coding agents default to deploying app changes here instead of installing on
real devices, as described in `AGENTS.md`.

The script builds for that simulator, boots it if necessary, installs the app,
opens Simulator (or DeviceHub in newer Xcode installations), and launches the
new build. Subsequent runs preserve app data
and replace only RSS Reader's running process. Build products go into
`build/ios-simulator`. `make install` continues to target macOS and the real
iPhone; simulator installation is separate.

### Optional simslim integration

[simslim](https://github.com/MobAI-App/simslim) reduces simulator resource usage
by disabling background services. Install it if it is not already available:

```sh
brew install mobai-app/tap/simslim
```

Prefer a dedicated clone rather than changing a simulator used by other projects:

```sh
simslim clone <source-UDID> "RSS Reader"
make simulators
make slim-simulator SIMULATOR_ID=<clone-UDID>
```

This applies slimming without rebooting and verifies the profile and required
services before installing. It keeps the `icloud`, `web`, and `siri` categories
enabled for iCloud/Keychain, web/universal links, and Intelligence-related
services. Other services are disabled persistently on that simulator only.
Restore its stock services with `simslim off <UDID>`. Neither installer erases
simulator data or changes the shared runtime.

Inspect the selected simulator with `simslim status <UDID>` or
`simslim measure <UDID>`. Slimming does not give a simulator physical-device
capabilities: Apple Intelligence availability and iCloud behavior still need
real-device verification where applicable.
