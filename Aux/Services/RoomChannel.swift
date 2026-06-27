//
//  RoomChannel.swift
//  Aux
//
//  Owns a single Realtime channel for the room. It carries:
//    • the rooms-row update stream  → drives synced playback + phase
//    • dj_lineup / votes change pings → trigger a lightweight refetch
//    • messages insert stream        → appends chat
//    • presence                      → the audience + host election
//
//  Events are surfaced as an AsyncStream the RoomViewModel consumes. Presence
//  members are kept here so host election (earliest joiner) stays in one place.
//

import Foundation
import Supabase
import Realtime

enum RoomEvent {
    case roomUpdated(Room)
    case lineupChanged
    case votesChanged
    case messageInserted(ChatMessage)
    case presenceChanged
}

@MainActor
@Observable
final class RoomChannel {

    private(set) var members: [PresenceMember] = []

    let events: AsyncStream<RoomEvent>
    private let emit: AsyncStream<RoomEvent>.Continuation

    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private let roomID: String
    private var me: PresenceMember?

    init(roomID: String) {
        self.roomID = roomID
        (events, emit) = AsyncStream.makeStream()
    }

    var presentUserIDs: [String] { members.map(\.userId) }

    /// The longest-present member (earliest joiner, tiebreak on id). Deterministic
    /// across clients — used as the leader for auto-DJ rounds and as the failover
    /// leader when the on-deck DJ has left.
    var longestPresentID: String? {
        members.min {
            ($0.joinedAtMs, $0.userId) < ($1.joinedAtMs, $1.userId)
        }?.userId
    }

    func start(me: PresenceMember) async {
        guard channel == nil else { return }

        self.me = me
        let channel = supabase.channel("room:\(roomID)") { config in
            config.presence.key = me.userId
        }
        self.channel = channel

        let roomFilter = "id=eq.\(roomID)"
        let scopeFilter = "room_id=eq.\(roomID)"

        let roomStream = channel.postgresChange(
            UpdateAction.self, schema: "public", table: "rooms", filter: roomFilter)
        let lineupStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "dj_lineup", filter: scopeFilter)
        let voteStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "votes", filter: scopeFilter)
        let messageStream = channel.postgresChange(
            InsertAction.self, schema: "public", table: "messages", filter: scopeFilter)
        let presenceStream = channel.presenceChange()

        await channel.subscribe()
        try? await channel.track(me)

        tasks.append(Task { [weak self] in
            for await change in roomStream {
                guard let room = RealtimeDecode.decode(Room.self, from: change.record) else { continue }
                self?.emit.yield(.roomUpdated(room))
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in lineupStream { self?.emit.yield(.lineupChanged) }
        })
        tasks.append(Task { [weak self] in
            for await _ in voteStream { self?.emit.yield(.votesChanged) }
        })
        tasks.append(Task { [weak self] in
            for await change in messageStream {
                guard let msg = RealtimeDecode.decode(ChatMessage.self, from: change.record) else { continue }
                self?.emit.yield(.messageInserted(msg))
            }
        })
        tasks.append(Task { [weak self] in
            for await change in presenceStream {
                self?.applyPresence(change)
            }
        })
    }

    private func applyPresence(_ change: any PresenceAction) {
        var current = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })
        if let joins = try? change.decodeJoins(as: PresenceMember.self) {
            for member in joins { current[member.userId] = member }
        }
        if let leaves = try? change.decodeLeaves(as: PresenceMember.self) {
            for member in leaves { current.removeValue(forKey: member.userId) }
        }
        members = current.values.sorted { $0.joinedAtMs < $1.joinedAtMs }
        emit.yield(.presenceChanged)
    }

    /// Drop our presence (app backgrounded) without tearing down the channel.
    func untrack() async {
        if let channel { await channel.untrack() }
    }

    /// Re-announce our presence (app foregrounded).
    func retrack() async {
        if let channel, let me { try? await channel.track(me) }
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let channel { await channel.unsubscribe() }
        channel = nil
        members = []
        me = nil
    }
}
