# garage-vision

An iOS app that watches your driveway through the iPhone's front camera, and when
**your** car pulls in, opens the garage automatically.

Every ~second it sends a frame to a [Roboflow](https://roboflow.com) computer-vision
workflow that (1) detects a car inside a driveway zone, (2) reads its license plate,
and (3) checks it against your plate. On a match it fires an HTTP request to an ESP32,
which actuates the opener (or, for now, lights an LED to prove it works).

```
 front camera ──every ~1s──▶ Roboflow workflow ──▶ plate text
   (CameraManager)            (car → driveway zone        │
                               → plate → OCR)             ▼
                                                  matches your plate?
                                                          │ yes (+30s cooldown)
                                                          ▼
                                          GET http://<esp32>/open ──▶ ESP32 ──▶ garage
                                                  (ESP32Client)         (esp32/)
```

## How it works

| Piece | File |
|---|---|
| Front-camera capture (upright, un-mirrored frames) | [CameraManager.swift](garage-vision/CameraManager.swift), [FrameStore.swift](garage-vision/FrameStore.swift) |
| The ~1s detect→match→trigger loop | [DetectionEngine.swift](garage-vision/DetectionEngine.swift) |
| Roboflow call (embedded workflow, POSTed inline) | [RoboflowClient.swift](garage-vision/RoboflowClient.swift), [workflow.json](garage-vision/workflow.json) |
| ESP32 trigger (`GET /open`) | [ESP32Client.swift](garage-vision/ESP32Client.swift) |
| UI: preview, status, indicators, controls | [ContentView.swift](garage-vision/ContentView.swift) |
| Config + secrets | [AppConfig.swift](garage-vision/AppConfig.swift), `Secrets.swift` |
| Local Network permission primer | [LocalNetworkPrimer.swift](garage-vision/LocalNetworkPrimer.swift) |
| Video "test env" (replay a clip instead of the camera) | [VideoReplaySource.swift](garage-vision/VideoReplaySource.swift) |

The Roboflow workflow itself runs server-side: `car_detector (rfdetr-nano)` →
driveway-zone filter (a stateless point-in-polygon, scaled to the frame) → crop →
`license-plate-recognition` → GLM OCR → `plate_text`. It's embedded as
[workflow.json](garage-vision/workflow.json) and POSTed inline on every frame, so the
app never depends on Roboflow's saved-workflow deploy state.

## Setup

1. **Secrets** — copy the template and fill it in (it's git-ignored, never committed):
   ```sh
   cp Secrets.example.swift garage-vision/Secrets.swift
   ```
   Set `roboflowAPIKey` (app.roboflow.com/settings/api), `targetPlate` (your plate —
   spaces/case ignored), and `esp32Host` (the ESP32's IP, or `garage.local`).

2. **Open in Xcode**, select your iPhone, and run. On first launch:
   - Allow **Camera** access.
   - Allow **Local Network** access when prompted (needed to reach the ESP32 — see note below).

3. **ESP32** — flash and wire it per [esp32/README.md](esp32/README.md), then put its IP
   in `Secrets.swift`.

> **Run it on a real device.** The camera doesn't work in the Simulator (use the Video
> test env there instead). For 24/7 use, mount a phone facing the driveway, keep the app
> foregrounded, and disable auto-lock (the app does this while watching).

## Using it

- **Start** begins watching; the two pills show **Car in Driveway** and the **last plate
  read** (turns green on a match). On a match it calls the ESP32 and flashes an
  "Opened for <plate>" banner.
- **Test ESP32** fires the exact same `/open` call manually, to check wiring.
- **Camera / Video (Test env)** toggle swaps the live camera for a bundled replay clip —
  handy for testing indoors or in the Simulator.

## Calibrating the driveway zone

The zone is tuned to a reference frame. If the live camera frames it differently:

1. Run the app in **Camera** mode, tap **Save Frame** (saves the exact frame to Photos).
2. Redraw the zone in the Roboflow editor on that frame.
3. Refresh the embedded copy:
   ```sh
   export ROBOFLOW_API_KEY=...
   python3 scripts/pull_workflow.py
   ```
   To preview the current zone on a frame: `python3 scripts/overlay_zone.py <frame.jpg>`.

## Scripts

| Script | Purpose |
|---|---|
| [scripts/pull_workflow.py](scripts/pull_workflow.py) | Regenerate `workflow.json` from the live Roboflow zone (stateless, no-flip). |
| [scripts/overlay_zone.py](scripts/overlay_zone.py) | Draw the current zone on an image to check alignment. |
| [scripts/roboflow_smoke_test.swift](scripts/roboflow_smoke_test.swift) | Assert the workflow returns the expected output keys. |

## Notes / gotchas

- **Local Network permission**: a plain request to a LAN IP doesn't reliably trigger
  iOS's prompt, so the app opens a Network-framework connection on launch to force it.
  If it never appears, delete + reinstall the app. The phone and ESP32 must be on the
  **same WiFi**.
- **The replay video (`parking.mov`) is git-ignored** (too big for GitHub). The Video
  toggle is hidden gracefully when it's absent.
- The app sends frames **upright and un-mirrored**; the workflow has no flip step. The
  replay source mirrors its clip to match the live camera.
