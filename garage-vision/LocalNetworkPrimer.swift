//
//  LocalNetworkPrimer.swift
//  garage-vision
//
//  iOS gates LAN access behind the Local Network permission. A plain URLSession
//  request to a raw LAN IP doesn't reliably make iOS surface the prompt — so the
//  toggle never appears under Settings → <app>, and requests to the ESP32 silently
//  time out (works in the Simulator, which skips the gate). Opening an explicit
//  Network-framework connection to the device reliably triggers the prompt.
//

import Foundation
import Network

nonisolated final class LocalNetworkPrimer: @unchecked Sendable {
    static let shared = LocalNetworkPrimer()

    private let lock = NSLock()
    private var connection: NWConnection?

    /// Open a short-lived TCP connection to the ESP32 to surface the Local Network
    /// prompt. Safe to call on every launch (no-op once the user has decided).
    /// `rawHost` may be "ip", "ip:port", or a name like "garage.local".
    func prime(host rawHost: String) {
        let parts = rawHost.split(separator: ":", maxSplits: 1)
        let host = String(parts.first ?? "")
        let port: UInt16 = parts.count > 1 ? (UInt16(parts[1]) ?? 80) : 80
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        lock.lock()
        connection?.cancel()
        connection = conn
        lock.unlock()
        conn.start(queue: .global(qos: .utility))
    }
}
