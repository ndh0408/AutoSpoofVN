<div align="center">

# LocationX

**Simulate GPS movement on iPhone — no jailbreak, no computer tethered to your device.**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2017.4%2B-lightgrey.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![CI](https://github.com/ndh0408/LocationX/actions/workflows/ci.yml/badge.svg)](https://github.com/ndh0408/LocationX/actions/workflows/ci.yml)

[Tiếng Việt](README.md) · English

</div>

---

## What LocationX is

LocationX is a native iOS app (SwiftUI) that simulates GPS movement: set a location by hand, drive
a real road-following route, script multi-step scenarios, run a 24/7 daily-life routine, or fly
between international airports.

What sets it apart from ordinary location changers is that it simulates **believable motion** —
acceleration, deceleration, road-following heading, time-correlated GPS noise — rather than teleporting
between coordinates.

> [!WARNING]
> This tool is for **testing, development and research on your own device**. Using it to cheat in
> games, deceive an employer, or anything else that violates a third party's terms of service is
> **your responsibility**. See [Disclaimer](#disclaimer).

---

## How it works

iOS does not let an ordinary app override the system-wide location. LocationX takes a different
route: it intercepts Apple's **WiFi positioning service**.

```
LocationX moves (route / scenario / routine / flight)
        │
        ▼
SimulationCoordinator  ← single source of truth for position
        │
        ▼
CoordinateServer  (local HTTP, 127.0.0.1:8765)
        │
        │   Shadowrocket fetches the script + live coordinates from here
        ▼
Shadowrocket (MITM)  intercepts  gs-loc.apple.com/clls/wloc
        │
        ▼
location-spoofer.js  decodes protobuf, replaces latitude/longitude, re-encodes
        │
        ▼
iOS believes the surrounding WiFi networks are at the spoofed coordinates
        │
        ▼
CoreLocation reports the spoofed position — with isSimulatedBySoftware = false
```

Protocol details live in [`Proxy/README.md`](Proxy/README.md).

### Why protobuf matters

The `gs-loc.apple.com` response is protobuf. The `Location` message is:

| Field | Name | Type | Unit |
|---:|---|---|---|
| 1 | `latitude` | int64 varint | 1e-8 degrees |
| 2 | `longitude` | int64 varint | 1e-8 degrees |
| 3 | `horizontal_accuracy` | int64 varint | — |

Varints are **variable length**, so you cannot overwrite them in place: changing the value changes
the byte count, which shifts every following field and invalidates the enclosing message lengths.
`location-spoofer.js` therefore decodes the whole message tree, rewrites the fields, and
**re-encodes bottom-up**.

The protobuf layout comes from the research in
[acheong08/apple-corelocation-experiments](https://github.com/acheong08/apple-corelocation-experiments).

---

## Features

| Area | What you get |
|---|---|
| **Map** | Full-bleed map, tap to set location, movement trail, follow mode, 3D tilt, three map styles |
| **Routes** | Multi-waypoint routes that follow real roads via MapKit, travel mode and speed, preview, save, re-run, GPX import/export |
| **Scenarios** | Action sequences: move, wait, dwell, change speed, wander, loop |
| **24/7 routine** | Automatic daily rhythm between home, work and cafe based on time of day |
| **Flight** | Great-circle flights between international airports with takeoff/cruise/descent phases, plus an automatic world-tour mode |
| **Telemetry** | Speed, heading, altitude, distance, progress, ETA — live |
| **Believable motion** | Per-vehicle acceleration curves, heading smoothing across the 0°/360° seam, time-correlated GPS noise |
| **Also** | Session history and replay, saved places, Live Activity / Dynamic Island, background execution, Vietnamese/English |

---

## Requirements

- **iPhone running iOS 17.4 or later**
- **macOS with Xcode 16** to build
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [**Shadowrocket**](https://apps.apple.com/app/shadowrocket/id932747118) (paid) to intercept and
  rewrite the positioning response. Surge / Loon / Stash work with the same module.
- An Apple Developer account to sign the app onto a real device

---

## Setup

### 1. Build

```bash
git clone https://github.com/ndh0408/LocationX.git
cd LocationX
xcodegen generate
open LocationX.xcodeproj
```

Pick the **LocationX** scheme, choose a destination, press ▶.

To run on a **real device**, set your signing team on all three targets (`LocationX`,
`LocationXTests`, `LocationXWidgets`) under *Signing & Capabilities*.

### 2. Set up Shadowrocket

Open LocationX → **Settings → Shadowrocket setup** and follow the in-app guide, or do it manually:

1. **Import the module**

   ```
   https://raw.githubusercontent.com/ndh0408/LocationX/main/Proxy/locationx.sgmodule
   ```

   Shadowrocket → *Config* → *Modules* → *Add Module* → paste the URL.

   For coordinates that follow LocationX **in real time**, use the local module instead — this
   requires LocationX to be running:

   ```
   http://127.0.0.1:8765/locationx.sgmodule
   ```

2. **Enable HTTPS decryption**

   Shadowrocket → *Settings* → *HTTPS Decryption* → on → *Generate Certificate* → *Install*.

3. **Trust the certificate** — the most commonly missed step, and the most common reason nothing works:

   *Settings* → *General* → *About* → *Certificate Trust Settings* → enable Shadowrocket's CA.

4. **Turn on the VPN** in Shadowrocket.

Once the chain is complete, LocationX reports **"Active"** — a state it only shows after Shadowrocket
has *actually* fetched the script from CoordinateServer, not as a guess.

### 3. Verify

Open Apple Maps. Your position should be the coordinate you set in LocationX.

> [!NOTE]
> Spoofing only takes effect while the device is positioning **via WiFi**. Outdoors, satellite GPS
> dominates and the real position wins. Toggling Airplane Mode and re-enabling WiFi forces the device
> back onto WiFi positioning.

---

## Project layout

```
LocationX/
├── Sources/
│   ├── Coordinator/     SimulationCoordinator — the single source of truth
│   ├── Engine/          Motion, routes, scenarios, routine, flight, device
│   │   ├── Route/       RouteSimulator, RouteBuilder, SavedRouteStore
│   │   ├── Motion/      MotionEngine, HeadingEngine
│   │   └── Scenario/    ScenarioEngine
│   ├── Models/          Domain types, state machine
│   ├── Persistence/     JSON storage, migrations
│   ├── UI/
│   │   ├── DesignSystem/  Color, type, spacing, motion and localization tokens
│   │   ├── Components/    Shared components
│   │   ├── Navigation/    RootTabView, AppRoute
│   │   ├── Map/           Map screen
│   │   ├── Routes/        Routes
│   │   ├── Flight/        Flight
│   │   └── Settings/      Settings
│   └── Views/           Screens not yet redesigned
├── Resources/           Info.plist, Assets, vi.lproj, en.lproj
LocationXWidgets/        Live Activity, Dynamic Island
LocationXTests/          Unit tests
Proxy/                   MITM module and protobuf script
docs/UI_AUDIT.md         Pre-redesign feature and risk inventory
```

### Architectural rules

`SimulationCoordinator` is the **single source of truth** for simulation state. Every coordinate
source goes through it, and it arbitrates by priority:

```
Manual 100 > Scenario 80 > Flight 60 > Route 50 > Routine 40 > Replay 20
```

The UI layer **observes** that state and never keeps a copy. GPS noise is applied exactly once, on
the way out to the device — the internal position stays true, otherwise noise accumulates into real
positional drift.

---

## Development

```bash
xcodegen generate                      # regenerate after editing project.yml
xcodebuild -project LocationX.xcodeproj -scheme LocationX \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

To add a UI string, use `L("your.key")` and add it to **both**
`Resources/vi.lproj/Localizable.strings` and `en.lproj/Localizable.strings`.
`LocalizationTests` fails the build if one side is missing or the `%d`/`%@` specifiers disagree.

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions.

---

## Disclaimer

This software is provided for educational and research purposes. The author is **not** responsible
for how you use it.

- Use it only on a device **you own**.
- Location spoofing may violate the terms of service of many apps and can lead to account bans.
- In some jurisdictions, misrepresenting your location to certain services may be unlawful.
- Do not use it to deceive people, commit fraud, or evade legal obligations.

---

## Credits

- [acheong08/apple-corelocation-experiments](https://github.com/acheong08/apple-corelocation-experiments) — Apple WiFi positioning protocol research
- [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer) — reference architecture for the MITM approach

---

## License

[Apache License 2.0](LICENSE) — © 2026 Nguyễn Đức Huy
