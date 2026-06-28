//
//  DMChannel.swift
//  Aux
//
//  Realtime for one open DM thread — new messages stream in (same pattern as
//  RoomChannel's room chat).
//

import Foundation
import Supabase
import Realtime

@MainActor
@Observable
final class DMChannel {
    let events: AsyncStream<DMMessage>
    private let emit: AsyncStream<DMMessage>.Continuation

    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private let dmID: String

    init(dmID: String) {
        self.dmID = dmID
        (events, emit) = AsyncStream.makeStream()
    }

    func start() async {
        guard channel == nil else { return }
        let channel = supabase.channel("dm:\(dmID)")
        self.channel = channel

        let stream = channel.postgresChange(
            InsertAction.self, schema: "public", table: "dm_messages",
            filter: "dm_id=eq.\(dmID)")

        await channel.subscribe()

        tasks.append(Task { [weak self] in
            for await change in stream {
                guard let message = RealtimeDecode.decode(DMMessage.self, from: change.record) else { continue }
                self?.emit.yield(message)
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
