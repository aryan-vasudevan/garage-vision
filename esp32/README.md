# ESP32 garage trigger

The iPhone app sends `GET http://<esp32Host>/open` when it matches the license
plate. [garage_trigger/garage_trigger.ino](garage_trigger/garage_trigger.ino)
runs a tiny web server on the ESP32 and **latches an output pin HIGH** on `/open`.

For now that pin lights an **LED** so you can confirm it works (powered from your
laptop, sitting in the car). Later, the same pin drives a **relay** that presses
the garage opener — no app changes needed.

## Upload

1. In Arduino IDE: **Boards Manager → install "esp32" by Espressif**.
2. Open the sketch, fill in `WIFI_SSID` / `WIFI_PASSWORD` (and a static IP if you
   want — see below).
3. Select your board (e.g. *ESP32 Dev Module*) and the right port, then **Upload**.
4. Open **Serial Monitor @ 115200**. It prints the IP, e.g.
   `>>> Put this IP in Secrets.swift (esp32Host): 192.168.1.42`.
5. In [../garage-vision/Secrets.swift](../garage-vision/Secrets.swift) set
   `esp32Host` to that IP (path stays `/open`). Or use `garage.local`.

> The ESP32 and the iPhone must be on the **same WiFi**. First time the app talks
> to it, iOS shows a **Local Network** permission prompt — allow it.

## Wiring — LED (do this now)

GPIO23 → resistor → LED → GND. Any 220–470 Ω resistor; LED long leg (anode) toward
the resistor.

```
ESP32 GPIO23 ──[330Ω]──▶|──── GND
                        LED
                     (long leg toward the resistor)
```

The onboard LED (GPIO2) mirrors the state too, so you'll see it even with nothing
wired.

## Wiring — relay (later, to actuate the garage)

Use a 3.3V-logic relay module. The output pin switches the relay instead of the LED:

```
ESP32 GPIO23 ─── IN  ┌──────────┐
ESP32 5V (VIN) ─ VCC │  relay   │  COM ─┐ wire across the garage opener's
ESP32 GND ────── GND │  module  │  NO  ─┘ wall-button terminals
                     └──────────┘
```

Two notes for later:
- Many relay modules are **active-LOW** (IN LOW = energized). If yours is, either
  wire the bulb/opener to the **NC** contact, or flip the `HIGH`/`LOW` in
  `setOutput()`.
- A garage opener wants a **momentary press**, not a permanent close. When you get
  there, change `handleOpen()` to pulse: `setOutput(true); delay(500);
  setOutput(false);`. For now it latches on purpose so you can see it stay on.

## Endpoints

| Route | Does |
|---|---|
| `GET /open` | latch output HIGH (what the app calls) — returns 200 |
| `GET /reset` | output LOW again, to re-test |
| `GET /status` | `{"activated": true\|false}` |
| `GET /` | status page |

## Test flow

1. Upload, note the IP, set `esp32Host` in `Secrets.swift`, rebuild the app.
2. In the app tap **Test ESP32** → the LED latches ON (and `/open` returns 200, so
   the app shows the green "Opened" banner).
3. Visit `http://<ip>/reset` in a browser to turn it off and try again — or run a
   real detection so the matched plate fires it.

The latch clears on a power cycle (it lives in RAM); use `/reset` to clear it
manually.
