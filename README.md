# Ruckus Admin

A native macOS app for managing Ruckus Unleashed networks. It replaces the controller's web
dashboard with a faster, cleaner interface and talks to the controller the same way the browser
does, so nothing needs to be enabled or installed on the network.

## Install

1. Download `RuckusAdmin-<version>.zip` from the [latest release](https://github.com/spotdgtl/RuckusAdmin/releases/latest).
2. Unzip it and drag RuckusAdmin into your Applications folder.
3. Open it and sign in with your controller's address, username and password.

Requires macOS 15 or later. The app is notarized by Apple, keeps your password in your Keychain,
and updates itself (RuckusAdmin ▸ Check for Updates… checks right away). No controller handy?
Click **Browse demo data** on the login screen.

## What you get

- Dashboard with live throughput, clients by band, RF environment, alarms and recent events
- Access points, clients and Wi-Fi networks with the same actions as the web UI: restart, block,
  rename, create or edit networks
- RF Environment: what your access points hear on every channel and the quietest channel per band
- Every System, Administration and Services setting from the web UI
- An API explorer for sending raw requests to the controller

Tested with Unleashed 200.15.6.212 on an R710. Developer notes are in
[DEVELOPING.md](DEVELOPING.md) and [API-NOTES.md](API-NOTES.md).

## Licence

MIT, see [LICENSE](LICENSE).
