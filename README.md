# Windscribe Tester

Desktop app that tries Windscribe datacenters and protocols, then sorts the ones that connect by ping.

It reads the servers already stored by the Windscribe app (city and nickname), because `windscribe-cli locations` only prints log lines. A connection uses the datacenter nickname, for example `Magic City`.

## Requirements

- macOS
- [Windscribe](https://windscribe.com/) installed, logged in, and `windscribe-cli` on your PATH
- Python 3 with Tkinter (the python.org macOS installer includes it)

## Run

```bash
python3 windscribe_tester.py
```

Pick servers, choose protocols, then start the test. Each attempt disconnects, connects, and pings the target (default `1.1.1.1`).

The server list comes from:

`~/Library/Preferences/com.windscribe.Windscribe2.plist`

That file stays on your Mac. This repo does not contain account data.
