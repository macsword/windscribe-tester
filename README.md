# Windscribe Tester

Desktop app that tries Windscribe datacenters and protocols, then sorts the ones that connect by ping.

It reads the servers already stored by the Windscribe app (city and nickname), because `windscribe-cli locations` only prints log lines. A connection uses the datacenter nickname, for example `Magic City`.

## Requirements

- macOS or Windows 10/11
- [Windscribe](https://windscribe.com/) installed and logged in
- Python 3 with Tkinter (the python.org installer includes it)

## Run on macOS

```bash
python3 windscribe_tester.py
```

The CLI is usually `/usr/local/bin/windscribe-cli`. Servers are read from:

`~/Library/Preferences/com.windscribe.Windscribe2.plist`

## Run on Windows

Double-click `run-windows.bat`, or from a terminal:

```bat
py -3 windscribe_tester.py
```

The CLI is usually `C:\Program Files\Windscribe\windscribe-cli.exe`. Servers are read from:

`HKCU\Software\Windscribe\Windscribe2` value `wsnetSettings`

Ping uses `ping -n 3`. If the registry key is missing, the app falls back to `windscribe-cli locations`.

## What a test does

Pick servers, choose protocols, then start the test. Each attempt disconnects, connects by nickname, and pings the target (default `1.1.1.1`).

Settings stay on your computer. This repo does not contain account data.
