# Ruckus Admin

A native macOS app (SwiftUI, macOS 15+) that replaces the stock Ruckus Unleashed web
dashboard with a modern interface. It signs in to the controller the same way a browser
does and uses the same AJAX/XML API the web UI uses, so nothing needs to be enabled on
the controller.

Built and verified against Unleashed 200.15.6.212 (R710 master).

## Install

Download the latest `RuckusAdmin-<version>.zip` from the
[Releases page](https://github.com/spotdgtl/RuckusAdmin/releases), unzip it and drag
`RuckusAdmin.app` into Applications. The app is signed with Spot Digital's Developer ID, is
sandboxed, and needs macOS 15 or later.

The first launch shows the login screen; enter the controller address, username and password.
The password is stored in your login Keychain (optional) and the app reconnects automatically
next time. To explore the interface without a controller, click **Browse demo data** on the
login screen, or run the app with the `--demo` argument.

## Updates

The app updates itself with [Sparkle](https://sparkle-project.org). It checks `appcast.xml`
in this repository at launch and once an hour, downloads new versions in the background and
installs them on the next relaunch. **RuckusAdmin ▸ Check for Updates…** checks immediately,
and both behaviours can be turned off under Settings ▸ Updates. Every update is verified
against the EdDSA public key embedded in the app (`SUPublicEDKey`) and against the Developer ID
signature of the running copy before it is installed. The version is shown on the login screen,
at the bottom of the sidebar and under Settings ▸ About.

## Build from source

```bash
open RuckusAdmin.xcodeproj
```

Press Run. Signing is automatic with the Spot Digital team; to build your own copy, pick your
team under Signing & Capabilities (or change `DEVELOPMENT_TEAM` in the project file). Sparkle is
fetched by Swift Package Manager on the first build. From the command line:

```bash
xcodebuild -project RuckusAdmin.xcodeproj -scheme RuckusAdmin -configuration Debug build
```

## Releasing

```bash
scripts/release.sh 1.0.1 "What changed"
```

The script archives a Release build, exports it signed with Developer ID, notarizes and staples
it (when a `RuckusAdmin` keychain profile for `notarytool` exists; create it once with
`xcrun notarytool store-credentials RuckusAdmin --apple-id <apple id> --team-id HCJTB3TKCY`),
zips it, signs the zip with the Sparkle key in your login Keychain, creates a GitHub release
carrying the zip, and commits the new entry to `appcast.xml`. The build number is the commit
count, so it always increases; the version is whatever you pass in. Running copies pick the
release up at their next check. Back up the Sparkle private key with `generate_keys -x <file>`
(the tool lives in `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`).

## What it shows

| Section | Data |
| --- | --- |
| Dashboard | System name, model, firmware, uptime, internet status, AP/client/WLAN/alarm counts, live throughput chart (one-minute buckets), clients by band, top clients, recent events |
| Access Points | Sortable table (status, model, IP, MAC, clients, channels, uptime, firmware); inspector with CPU/memory, radios, interfaces, traffic history, clients, raw attributes; edit name/location/radio overrides; restart |
| Clients | Searchable table (device, AP, network, band/channel, signal in dBm as received by the AP, traffic, first seen); inspector with full details; rename, favourite, block/unblock, disconnect |
| Wi-Fi Networks | Cards per WLAN with security, VLAN, guest/hidden flags, clients and traffic history; enable/disable; create, edit and delete networks |
| RF Environment | What the APs' background scans hear: per-band channel usage chart of neighbouring BSSIDs (position = channel, width = assumed channel width, height = signal), channel congestion score with least/busiest channel, your radios, neighbour table |
| Events & Alarms | Filterable by kind and severity, searchable |
| API Explorer | Send any `<ajax-request>` to `_cmdstat.jsp` / `_conf.jsp`, with presets and a log of every request the app made |

## Settings

The three Admin & Services menus of the web UI are reproduced under **Settings** in the sidebar.
Element-based pages are declared in `Settings/SettingsCatalog.swift`: each page lists the
`system` elements it reads and the fields it edits, and the generic `ConfigPageView` writes them
back with `setconf comp='system'` and `IS_PARTIAL='true'`, exactly as the stock forms do. List
pages (`ListPageView`) use `getconf` / `addobj` / `updobj` / `delobj` on the list component.

| Group | Pages |
| --- | --- |
| System | System Info (name, preferred master), IP Settings, System Time, Country Code, Roles, Users, Mesh |
| Administration | Preferences (language, timeout, admin password), Backup & Restore (download backup, restore saved, reboot, factory reset), Upgrade (AP image state), Diagnostics (syslog, ping/traceroute from an AP), Certificate, Network Management (SNMP v2/v3/traps, UMM, syslog), Remote Management (WAN services, mobile app), Technical Support |
| Services | AAA Servers, Access Control (L2/L3/device policies), Application Recognition & Control, Bonjour Gateway, Dynamic PSK, Guest Access Service, Hotspot Services, Radio Control (self healing, background scan, load/band balancing, radar pre-scan), WIPS, URL Filtering, Wi-Fi Calling |

Pages whose rule editors are complex (L3 rules, ARC policies, URL filtering categories) are
read-only here with a link to the web UI; everything else is editable. A page only writes the
elements whose fields you changed, and blank password fields are never sent (they mean "keep
the current secret"). The attribute names for new AAA servers and hotspot profiles follow the
ZoneDirector schema and have not been verified against this firmware yet.

Verified live on 2026-11-02: changing the syslog level (Network Management) round-tripped
through `setconf` and read back correctly.

### Headless mode

For scripting or testing, the app can apply a settings change without showing a window:

```bash
RuckusAdmin.app/Contents/MacOS/RuckusAdmin --set network-management log.level=2
```

It connects with the stored Keychain password, loads the page, applies `path.attribute=value`
assignments through the same code the UI uses, prints the request, the controller's reply and
the read-back value, and exits. Page ids are the `id` values in `SettingsCatalog.swift`.

## RF environment: what the data can and cannot say

Unleashed APs have no spectrum-analyser API; what they report is the result of background
scanning (Wi-Fi frames only). The chart therefore shows neighbouring networks, not non-Wi-Fi
interference such as microwave ovens or cordless phones. Signal values are dB above the AP's
noise floor as measured at the AP.

## How it talks to the controller

- `POST /admin/login.jsp` with `username`, `password`, `ok=Log in` (form-encoded). A
  302 means success; a 200 containing `<meta http-equiv="X-Auth" content="Unauthorized">`
  means bad credentials. The session cookie is `-ejs-session-`.
- The CSRF token comes from the `HTTP_X_CSRF_TOKEN` response header or the
  `var csfrToken = '…'` script on `dashboard.jsp`, and is sent as `X-CSRF-Token`.
- Reads: `POST /admin/_cmdstat.jsp` (`getstat`, `docmd`) and `POST /admin/_conf.jsp`
  (`getconf`, `updobj`, …) with an XML body and
  `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`, mirroring the web UI.
- A 302 or the Unauthorized marker on any request triggers one transparent re-login.
- The self-signed certificate is trusted on first use and its SHA-256 fingerprint pinned
  per host (Settings ▸ Certificate).

Polling runs every 20 s by default (Settings ▸ Refresh) and makes the same requests the
web dashboard makes once a minute. **Live mode** (Auto-refresh menu ▸ Live, or launch with
`--live`) adds a fast lane that samples two small statistics requests every 3 s. The controller
only updates the master AP's Ethernet port counters in real time (wireless and per-client counters
refresh about once a minute, traffic history buckets every 60 s, background scans every 5 min), so
the live throughput chart is computed from the WAN port counters and per-client rates are averages
over the controller's last update interval. The regular polling continues:

| Request | Purpose |
| --- | --- |
| `getstat stamgr` with `wlan`, `ap`, `client LEVEL=2`, `apsummary` | WLAN/AP stats, clients, fleet traffic history |
| `getstat stamgr` with `ap LEVEL=2` | Detailed AP data (uptime, CPU, memory, interfaces) |
| `getconf ap-list`, `getconf wlansvc-list` | Names, locations, WLAN configuration |
| `getstat system` with `sysinfo`, `identity`, `mgmt-ip`, … | Controller identity and uptime |
| `getstat stamgr` with `system LEVEL=1` | Network-wide totals and Ethernet ports |
| `docmd get-connect-status` | Internet connectivity |
| `getstat eventd` (`xevent`, `alarm`) | Events and alarms, every third poll |

## Layout

```
RuckusAdmin/
├── RuckusAdminApp.swift       App entry, menu commands, Settings scene
├── API/
│   ├── RuckusSession.swift    Login, CSRF, cookies, TLS trust, request plumbing
│   ├── LiveRuckusService.swift  The requests above, mapped into models
│   ├── RuckusParsers.swift    XML attribute → model mapping
│   ├── DemoRuckusService.swift  Generated sample network
│   ├── XMLNode.swift          Small XML tree parser
│   └── CertificateTrust.swift Trust-on-first-use fingerprint store
├── Models/Models.swift        AccessPoint, WirelessClient, WLAN, ControllerEvent, …
├── Store/ControllerStore.swift  Observable state, polling, actions
├── Views/                     Login, main window, dashboard, tables, inspectors, explorer, settings
└── Support/                   Keychain, formatters
```
