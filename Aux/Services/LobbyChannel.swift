//
//  LobbyChannel.swift
//  Aux
//
//  One realtime subscription to the whole `rooms` table — drives the live lobby
//  (audience count, on-deck DJ + track, lineup length) without per-room presence.
//  Counts come from the denormalized columns the room leaders keep fresh.
//

import Foundation
import Supabase
import Realtime

@MainActor
@Observable
final class LobbyChannel {

    let events: AsyncStream<Room>
    private let emit: AsyncStream<Room>.Continuation

    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []

    init() {
        (events, emit) = AsyncStream.makeStream()
    }

    func start() async {
        guard channel == nil else { return }
        let channel = supabase.channel("lobby:rooms")
        self.channel = channel

        let roomStream = channel.postgresChange(
            UpdateAction.self, schema: "public", table: "rooms")

        await channel.subscribe()

        tasks.append(Task { [weak self] in
            for await change in roomStream {
                guard let room = RealtimeDecode.decode(Room.self, from: change.record) else { continue }
                self?.emit.yield(room)
            }
        })
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let channel { await channel.unsubscribe() }
        channel = nil
    }
}
