/*
 * garage_trigger.ino — ESP32 endpoint for the garage-vision app.
 *
 * The iPhone app sends an HTTP GET to /open when it sees the matching license
 * plate. This sketch latches OUTPUT_PIN HIGH on /open and keeps it there, so you
 * can verify with an LED now and swap in a relay (to actuate the garage) later.
 *
 * Board:     any ESP32 dev board (e.g. ESP32 DevKit V1).
 * Setup:     install the "esp32" board package by Espressif (Boards Manager).
 * Libraries: all built into the ESP32 core (WiFi, WebServer, ESPmDNS).
 *
 * Endpoints:
 *   GET /        -> status page
 *   GET /open    -> latch output HIGH (what the app calls)  [returns 200]
 *   GET /reset   -> set output LOW again (to re-test)
 *   GET /status  -> {"activated": true|false}
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>

// ============ FILL THESE IN ============
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Optional: pin a static IP so the app's esp32Host never changes between reboots.
// Leave false to use DHCP (read the assigned IP from the Serial Monitor).
#define USE_STATIC_IP false
IPAddress STATIC_IP (192, 168, 1, 50);
IPAddress GATEWAY   (192, 168, 1, 1);
IPAddress SUBNET    (255, 255, 255, 0);
IPAddress DNS_SERVER(8, 8, 8, 8);
// =======================================

const int OUTPUT_PIN = 23;   // LED now (via resistor), relay later
const int STATUS_LED = 2;    // onboard LED on most ESP32 dev boards (mirrors state)

WebServer server(80);
bool activated = false;

void setOutput(bool on) {
    activated = on;
    digitalWrite(OUTPUT_PIN, on ? HIGH : LOW);
    digitalWrite(STATUS_LED, on ? HIGH : LOW);
}

void handleOpen() {
    setOutput(true);                       // latch ON until /reset or a reboot
    Serial.println("/open  -> output LATCHED HIGH");
    server.send(200, "text/plain", "OK: output activated");
}

void handleReset() {
    setOutput(false);
    Serial.println("/reset -> output LOW");
    server.send(200, "text/plain", "OK: output reset");
}

void handleStatus() {
    server.send(200, "application/json",
                String("{\"activated\":") + (activated ? "true" : "false") + "}");
}

void handleRoot() {
    String html = "<h2>garage-vision ESP32</h2><p>Output: <b>";
    html += activated ? "ACTIVATED" : "idle";
    html += "</b></p><p><a href=\"/open\">/open</a> &middot; "
            "<a href=\"/reset\">/reset</a> &middot; <a href=\"/status\">/status</a></p>";
    server.send(200, "text/html", html);
}

void setup() {
    Serial.begin(115200);
    pinMode(OUTPUT_PIN, OUTPUT);
    pinMode(STATUS_LED, OUTPUT);
    setOutput(false);

    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
#if USE_STATIC_IP
    if (!WiFi.config(STATIC_IP, GATEWAY, SUBNET, DNS_SERVER)) {
    Serial.println("Static IP config failed, falling back to DHCP");
    }
#endif
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    Serial.print("Connecting to WiFi");
    while (WiFi.status() != WL_CONNECTED) { delay(400); Serial.print("."); }
    Serial.println();
    Serial.print(">>> Put this IP in Secrets.swift (esp32Host): ");
    Serial.println(WiFi.localIP());

    // Bonus: also reachable as http://garage.local (so esp32Host can be a name,
    // not an IP that might change). iOS resolves .local over Bonjour.
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
