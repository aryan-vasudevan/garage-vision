# ESP32 garage trigger

The iPhone app sends `GET http://<esp32Host>/open` when it matches the license
plate. [garage_trigger/garage_trigger.ino](garage_trigger/garage_trigger.ino)
runs a tiny web server on the ESP32 and, on `/open`, **pulses a relay closed for
~400 ms** — exactly like a finger tapping the garage wall button.

You can bench-test with just the onboard LED first, then wire the relay to the opener.

## Upload

1. In Arduino IDE: **Boards Manager → install "esp32" by Espressif**.
2. Open the sketch, fill in `WIFI_SSID` / `WIFI_PASSWORD`, and set `RELAY_ACTIVE_LOW`
   (see below).
3. Select your board (e.g. *ESP32 Dev Module*) + port, then **Upload**.
4. Open **Serial Monitor @ 115200** → note the IP it prints, e.g.
   `>>> Put this IP in Secrets.swift (esp32Host): 10.0.0.214`.
5. Put that IP in [../garage-vision/Secrets.swift](../garage-vision/Secrets.swift)
   (`esp32Host`), or use `garage.local`.

> Tip: set `USE_STATIC_IP true` and pin the IP you already use in the app, so DHCP
> can't change it on you.

> The ESP32 and the iPhone must be on the **same WiFi**. First time the app talks to
> it, iOS shows a **Local Network** prompt — allow it.

## Bench test (no relay yet)

The onboard LED (GPIO2) blinks for ~400 ms on each `/open`, so you can verify the
whole chain before touching the opener. Tap **Test ESP32** in the app, or visit
`http://<ip>/open` in a browser — the LED should blink.

## Wiring to the garage opener

A wall button is a **momentary dry-contact switch**: pressing it shorts two
terminals for a moment, and *that* tells the opener to go (the voltage across them
is low-voltage, **not** mains). So you replace the button with a relay:

```
Opener button contact A ──── Relay COM
Opener button contact B ──── Relay NO      (relay closed for 400ms = "button tapped")

ESP32 GPIO27 ──── relay IN
ESP32 5V (or 3V3) ── relay VCC
ESP32 GND ──────── relay GND

ESP32 GPIO26 ──[330Ω]──▶|── GND            (indicator bulb/LED — latches on)
```

- The two contacts are whichever pair you can bridge to make the **door** move (on
  multi-function consoles both buttons share the same two wires, so go by what actually
  moves the door, not the terminal labels). No multimeter needed — a wall button has
  two wires; bridge them to confirm. Those go to **COM + NO**.
- You can **leave the real button connected in parallel** — it still works by hand.
  **Don't tape it pressed** (that permanently shorts it; you want a momentary pulse).

### Relay polarity (important)

Most opto-isolated relay modules are **active-LOW** (IN low = relay closed), which is
the default `RELAY_ACTIVE_LOW true`. If yours is active-high, set it `false`. The
firmware forces the relay **open at boot** (first line of `setup()`) so it can't twitch
the door on power-up — but it's worth keeping `RELAY_PIN` on a clean GPIO
(**avoid strapping pins 0/2/4/5/12/15**; 27 is safe). For extra insurance on an
active-low module, add a 10 kΩ pull-up from IN to 3V3.

## Pins

| GPIO | Use |
|---|---|
| **27** | relay control (`IN`) — pulses the garage |
| **26** | indicator bulb/LED — latches on when triggered |
| 2 | onboard LED — mirrors the bulb |

## Endpoints

| Route | Does |
|---|---|
| `GET /open` | pulse the relay ~400 ms (garage) + latch the bulb on — 200; 4 s cooldown |
| `GET /reset` | clear the indicator bulb |
| `GET /status` | `{"bulb": ..., "last_trigger_ms_ago": ...}` |
| `GET /` | status page |

Optional auth: set `OPEN_TOKEN` in the sketch and `esp32Path = "/open?token=..."`
app-side so only the app can trigger the door.

## Safety recap

- Relay only — never wire the opener's terminals to a GPIO directly.
- The relay is **pulsed**, never latched; forced **open at boot**; and rate-limited by
  a cooldown (the app also enforces its own 30 s cooldown).
