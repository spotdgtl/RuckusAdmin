# Developing Ruckus Admin

## Build

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

## Headless mode

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
