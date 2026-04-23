import Foundation
import os

/// Listens to `public.orders` via Supabase Realtime WebSocket. When rows change, calls `onOrdersChanged`
/// on a background thread; the consumer should debounce and call `syncData` on the main actor.
final class SupabaseOrdersRealtimeService: @unchecked Sendable {
    private struct RealtimeState: Sendable {
        var isStopped = false
        var nextRef = 2
    }

    private let config: SupabaseConfig
    private let onOrdersChanged: @Sendable () -> Void
    private var runTask: Task<Void, Never>?
    private let state = OSAllocatedUnfairLock(initialState: RealtimeState())

    init(config: SupabaseConfig, onOrdersChanged: @escaping @Sendable () -> Void) {
        self.config = config
        self.onOrdersChanged = onOrdersChanged
    }

    func start() {
        state.withLock { $0.isStopped = false }
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.runWithReconnect()
        }
    }

    func stop() {
        state.withLock { $0.isStopped = true }
        runTask?.cancel()
        runTask = nil
    }

    private var shouldStop: Bool {
        state.withLock { $0.isStopped }
    }

    private func runWithReconnect() async {
        var delaySeconds: Double = 1
        while !Task.isCancelled, !shouldStop {
            let token = SupabaseSessionAccess.accessToken
            guard let token, !token.isEmpty else {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }
            do {
                try await connectOneSession(accessToken: token)
                delaySeconds = 1
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled || shouldStop { return }
                AppTelemetry.track(error: "supabase_realtime_session_error")
                let nanos = UInt64(min(30, max(1, delaySeconds)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                delaySeconds = min(30, delaySeconds * 1.6)
            }
        }
    }

    private func connectOneSession(accessToken: String) async throws {
        var c = URLComponents()
        c.scheme = "wss"
        c.host = config.projectURL.host
        c.path = "/realtime/v1/websocket"
        c.queryItems = [
            URLQueryItem(name: "apikey", value: config.anonKey),
            URLQueryItem(name: "vsn", value: "2.0.0")
        ]
        guard let wsURL = c.url else { throw URLError(.badURL) }

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: wsURL)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        let joinPayload: [String: Any] = [
            "config": [
                "broadcast": [
                    "ack": false,
                    "self": false
                ] as [String: Any],
                "postgres_changes": [
                    [
                        "event": "*",
                        "schema": "public",
                        "table": "orders"
                    ] as [String: Any]
                ] as [Any]
            ] as [String: Any],
            "access_token": accessToken
        ]
        let joinMessage: [Any] = ["1", "1", "realtime:public:orders", "phx_join", joinPayload]
        try await sendPhoenixArray(joinMessage, on: socket)

        let heartbeat = Task { await self.heartbeatRun(on: socket) }
        defer { heartbeat.cancel() }
        try await receiveLoop(socket: socket)
    }

    private func heartbeatRun(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled, !shouldStop {
            do {
                try await Task.sleep(nanoseconds: 20_000_000_000)
            } catch {
                return
            }
            if Task.isCancelled || shouldStop { return }
            let ref = state.withLock { s in
                let n = s.nextRef
                s.nextRef += 1
                return String(n)
            }
            let emptyDict: [String: Any] = [:]
            let beat: [Any] = [NSNull(), ref, "phoenix", "heartbeat", emptyDict]
            do {
                try await sendPhoenixArray(beat, on: socket)
            } catch {
                return
            }
        }
    }

    private func receiveLoop(socket: URLSessionWebSocketTask) async throws {
        while !Task.isCancelled, !shouldStop {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await withCheckedThrowingContinuation { cont in
                    socket.receive { cont.resume(with: $0) }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
            if Task.isCancelled || shouldStop { return }
            if case .string(let text) = message, isPostgresOrdersChangeEvent(jsonText: text) {
                onOrdersChanged()
            }
        }
    }

    private func isPostgresOrdersChangeEvent(jsonText: String) -> Bool {
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count > 3,
              let event = root[3] as? String
        else { return false }
        if event == "postgres_changes" { return true }
        if event == "phx_reply", let payload = root[4] as? [String: Any], let status = payload["status"] as? String, status == "error" {
            AppTelemetry.track(error: "supabase_realtime_join_rejected")
        }
        return false
    }

    private func sendPhoenixArray(_ value: [Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        guard let string = String(data: data, encoding: .utf8) else { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            socket.send(.string(string)) { err in
                if let err { c.resume(throwing: err) } else { c.resume() }
            }
        }
    }
}
