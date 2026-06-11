/*
 * garage_trigger.ino — ESP32 endpoint for the garage-vision app.
 *
 * On GET /open the app's matched plate triggers two things:
 *   - RELAY_PIN  : PULSES a relay closed ~400 ms (like tapping the wall button)
 *                  to actuate the garage. Wire the relay COM+NO across the two
 *                  door-button contacts you confirmed move the door.
 *   - BULB_PIN   : LATCHES an indicator bulb/LED ON (stays lit until /reset or a
 *                  reboot) so you can see at a glance that it fired.
 *
 * Board:     any ESP32 dev board (e.g. ESP32 DevKit V1).
 * Setup:     install the "esp32" board package by Espressif (Boards Manager).
 * Libraries: all built into the ESP32 core (WiFi, WebServer, ESPmDNS).
 *
 * SAFETY: never wire the garage straight to a GPIO — always through the relay
 * (isolation; the opener's button voltage can exceed 3.3 V). The relay is only
 * ever PULSED, and is forced open at boot.
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>

// ================= FILL THESE IN =================
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Most opto-isolated relay modules are ACTIVE-LOW (IN low = relay closed).
// If yours closes when the pin is HIGH instead, set this to false.
#define RELAY_ACTIVE_LOW   true

const int RELAY_PIN  = 27;    // relay -> garage   (5V side; safe, non-strapping)
const int BULB_PIN   = 26;    // indicator bulb/LED (5V side; latches on trigger)
const int STATUS_LED = 2;     // onboard LED, mirrors the bulb
const int PULSE_MS   = 400;   // how long the relay (garage "button") is held

const unsigned long COOLDOWN_MS = 4000;   // ignore repeat /open within this window

// Optional shared secret: require /open?token=THIS so only the app can trigger.
// Leave "" to disable. (App-side: set esp32Path to "/open?token=THIS".)
const char* OPEN_TOKEN = "";

// Optional static IP so esp32Host never changes (else DHCP — read Serial Monitor).
#define USE_STATIC_IP false
IPAddress STATIC_IP (10, 0, 0, 214);
IPAddress GATEWAY   (10, 0, 0, 1);
IPAddress SUBNET    (255, 255, 255, 0);
IPAddress DNS_SERVER(8, 8, 8, 8);
// =================================================

WebServer server(80);
unsigned long lastTriggerMs = 0;
bool bulbOn = false;

inline void relayOff() { digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);  }
inline void relayOn()  { digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? LOW  : HIGH); }

void setBulb(bool on) {
    bulbOn = on;
    digitalWrite(BULB_PIN, on ? HIGH : LOW);
    digitalWrite(STATUS_LED, on ? HIGH : LOW);
}

void handleOpen() {
    if (OPEN_TOKEN[0] != '\0' && server.arg("token") != String(OPEN_TOKEN)) {
        server.send(403, "text/plain", "forbidden");
        return;
    }
    unsigned long now = millis();
    if (lastTriggerMs != 0 && now - lastTriggerMs < COOLDOWN_MS) {
        server.send(200, "text/plain", "OK: cooldown, ignored");
        return;
    }
    lastTriggerMs = now;
    server.send(200, "text/plain", "OK: triggered");   // reply first

    // Pulse the relay = one garage button press.
    relayOn();
    delay(PULSE_MS);
    relayOff();

    // Latch the indicator on (clear with /reset).
    setBulb(true);
    Serial.println("/open -> relay pulsed, bulb latched ON");
}

void handleReset() {
    setBulb(false);
    Serial.println("/reset -> bulb cleared");
    server.send(200, "text/plain", "OK: indicator cleared");
}

void handleStatus() {
    String body = "{\"bulb\":";
    body += bulbOn ? "true" : "false";
    body += ",\"last_trigger_ms_ago\":";
    body += (lastTriggerMs == 0) ? "null" : String(millis() - lastTriggerMs);
    body += "}";
    server.send(200, "application/json", body);
}

void handleRoot() {
    String html = "<h2>garage-vision ESP32</h2><p>Bulb: <b>";
    html += bulbOn ? "ON" : "off";
    html += "</b></p><p><a href=\"/open\">/open</a> &middot; "
            "<a href=\"/reset\">/reset</a> &middot; <a href=\"/status\">/status</a></p>";
    server.send(200, "text/html", html);
}

void setup() {
    // SAFETY FIRST: pre-load the safe (relay-open) level into the output latch
    // BEFORE switching the pin to OUTPUT, so it can't dip LOW — which an active-low
    // relay reads as "pressed" — during boot. (A 10k pull-up from RELAY_PIN to 3V3
    // also holds it open in the brief window before this code runs.)
    relayOff();                  // set the output latch to the safe level first
    pinMode(RELAY_PIN, OUTPUT);  // now it drives OUTPUT already at the safe level
    relayOff();
    pinMode(BULB_PIN, OUTPUT);
    pinMode(STATUS_LED, OUTPUT);
    setBulb(false);

    Serial.begin(115200);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
#if USE_STATIC_IP
    WiFi.config(STATIC_IP, GATEWAY, SUBNET, DNS_SERVER);
#endif
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("Connecting to WiFi");
    while (WiFi.status() != WL_CONNECTED) { delay(400); Serial.print("."); }
    Serial.println();
    Serial.print(">>> Put this IP in Secrets.swift (esp32Host): ");
    Serial.println(WiFi.localIP());

    if (MDNS.begin("garage")) {
        MDNS.addService("http", "tcp", 80);
        Serial.println(">>> Also reachable at http://garage.local");
    }

    server.on("/",       handleRoot);
    server.on("/open",   handleOpen);
    server.on("/reset",  handleReset);
    server.on("/status", handleStatus);
    server.begin();
    Serial.println("HTTP server started on port 80");
}

void loop() {
    server.handleClient();
}
