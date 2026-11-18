# Windscribe Tester

Native macOS app that tries Windscribe datacenters and protocols, then ranks the ones that connect by ping.

It reads the servers already stored by the Windscribe app (city, nickname, region, 10 Gbps, Pro, P2P). Connect uses the datacenter nickname, for example `Magic City`.

Requires **macOS 14+**, and [Windscribe](https://windscribe.com/) installed and logged in.

## Install

Download the latest build from the [releases page](https://github.com/macsword/windscribe-tester/releases/latest).

- **macOS 14+:** open `WindscribeTester-macOS.dmg` and drag **Windscribe Tester** into Applications. The app is not notarized, so the first launch needs a right-click and Open.
- **Windows:** use the [v1.0.0 Python build](https://github.com/macsword/windscribe-tester/releases/tag/v1.0.0), or run `legacy/windscribe_tester.py`. Version 2 is macOS-only.

Windscribe must already be installed and logged in. These builds do not include your account.

## Features

- Sidebar of live datacenters, grouped by continent and region
- Search plus 10G / P2P / Pro filters
- Queue whole regions, visible matches, or a custom nickname
- Protocol chips: WireGuard, IKEv2, UDP, TCP, Stealth, WS Tunnel
- Sequential connect + ping tests with live progress and ETA
- Results table sorted by ping, double-click or **Connect to Best**
- Optional stay-connected-to-winner when a run finishes
- Export CSV, persist queue and settings locally
- Current Windscribe login / connection / IP in the toolbar

This app does not include your account.

## Build

```bash
xcodegen generate
xcodebuild -scheme WindscribeTester -configuration Release -derivedDataPath DerivedData
open "DerivedData/Build/Products/Release/Windscribe Tester.app"
```

Or open `WindscribeTester.xcodeproj` in Xcode and Run.

The CLI is usually `/usr/local/bin/windscribe-cli`. Servers are read from:

`~/Library/Preferences/com.windscribe.Windscribe2.plist`

If that file is missing, the app falls back to `windscribe-cli locations`.

## What a test does

Pick servers, choose protocols, then start the test. Each attempt disconnects, connects by nickname, waits until Connected or timeout, and pings the target (default `1.1.1.1`).

Settings stay on your computer.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘↩ | Start test |
| ⌘. | Cancel |
| ⌘R | Reload servers |
| ⌘⇧A | Select all visible servers |
| ⌘B | Connect to best result |
| ⌘⇧E | Export CSV |
| ⌘, | Settings |

## Previous Python app

The original Tkinter version for macOS and Windows is in `legacy/`.
