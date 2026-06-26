//
//  RoomViewModel.swift
//  Aux
//
//  The room's brain. Owns the clock, realtime channel, rotation engine and
//  playback; exposes derived state for the (dumb) views; and turns user taps into
//  RPC calls. Everything time-based is recomputed off `tick` / playback position
//  so SwiftUI refreshes smoothly.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoomViewModel {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// What the room is doing *for the local user* this round.
    enum RoundStage {
        case idle       // bootstrapping / nothing yet
        case voting     // clip playing, votes open
        case reveal     // clip ended, showing who voted what
        case picking    // on-deck DJ is choosing
    }

    let profile: UserProfile
    let playback = PlaybackController()
    let serverClock = ServerClock()

    private let roomID = RoomConfig.roomID
    private let channel: RoomChannel
    private let engine: RoomEngine
    private let roomService = RoomService()
    private let lineupService = LineupService()
    private let voteService = VoteService()
    private let chatService = ChatService()

    // Observable state
    var loadState: LoadState = .loading
    private(set) var room: Room?
    private(set) var lineup: [LineupEntry] = []
    private(set) var votes: [Vote] = []
    private(set) var messages: [ChatMessage] = []
    private(set) var djHotVotes = 0
    private(set) var djTotalVotes = 0
    var tick = 0   // bumped twice a second to refresh time-based UI

    private var started = false
    private var eventTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var currentRoundID: String?

    init(profile: UserProfile) {
        self.profile = profile
        self.channel = RoomChannel(roomID: RoomConfig.roomID)
        self.engine = RoomEngine(roomID: RoomConfig.roomID)
    }

    // MARK: - Derived state

    var audience: [PresenceMember] { channel.members }
    var isHost: Bool { channel.hostID == profile.id }
    var amOnDeck: Bool { room?.currentDjId == profile.id }
    var amInLineup: Bool { lineup.contains { $0.userId == profile.id } }
    var myCuedTrack: Track? { lineup.first { $0.userId == profile.id }?.cuedTrack }
    var onDeckTrack: Track? { room?.currentTrack }

    var onDeckName: String {
        guard let dj = room?.currentDjId else { return "Auto-DJ" }
        return displayMember(dj).handle
    }
    var onDeckAvatar: String {
        guard let dj = room?.currentDjId else { return "🤖" }
        return displayMember(dj).avatar
    }

    /// Waiting DJs (everyone except whoever is on deck), in rotation order.
    var waitingLineup: [LineupEntry] {
        lineup.filter { $0.userId != room?.currentDjId }
    }

    var roundStage: RoundStage {
        guard let room else { return .idle }
        switch room.phase {
        case .idle: return .idle
        case .picking: return .picking
        case .playing:
            return playback.positionSeconds >= RoomConfig.clipDuration ? .reveal : .voting
        }
    }

    var progress: Double {
        guard RoomConfig.clipDuration > 0 else { return 0 }
        return min(1, max(0, playback.positionSeconds / RoomConfig.clipDuration))
    }

    var hotCount: Int { votes.filter { $0.vote == .hot }.count }
    var skipCount: Int { votes.filter { $0.vote == .skip }.count }
    var myVote: VoteKind? { votes.first { $0.voterId == profile.id }?.vote }

    var canVote: Bool {
        room?.roundId != nil && room?.currentTrack != nil &&
            (roundStage == .voting || roundStage == .reveal)
    }

    /// Each cast vote paired with the voter's display info — the reveal payload.
    var revealRows: [(member: PresenceMember, vote: VoteKind)] {
        votes.map { vote in
            let info = displayMember(vote.voterId)
            let member = PresenceMember(
                userId: vote.voterId, handle: info.handle,
                avatar: info.avatar, joinedAtMs: 0)
            return (member, vote.vote)
        }
        .sorted { $0.member.handle.lowercased() < $1.member.handle.lowercased() }
    }

    var djHotRatingText: String? {
        guard room?.currentDjId != nil, djTotalVotes > 0 else { return nil }
        let pct = Int((Double(djHotVotes) / Double(djTotalVotes) * 100).rounded())
        return "\(pct)% 🔥 over \(djTotalVotes) vote\(djTotalVotes == 1 ? "" : "s")"
    }

    var pickingSecondsLeft: Int? {
        _ = tick
        guard room?.phase == .picking, let deadline = room?.phaseDeadline else { return nil }
        return max(0, Int(serverClock.now.seconds(until: deadline).rounded(.up)))
    }

    func displayMember(_ userID: String) -> (handle: String, avatar: String) {
        if let m = audience.first(where: { $0.userId == userID }) { return (m.handle, m.avatar) }
        if userID == profile.id { return (profile.handle, profile.avatar) }
        return ("someone", "🎧")
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true

        playback.configureAudioSession()
        playback.attach(clock: serverClock)
        playback.start()
        serverClock.start()
        await serverClock.calibrate()

        do {
            apply(room: try await roomService.fetchRoom(id: roomID))
        } catch {
            loadState = .failed(message(for: error))
            return
        }
        await refreshLineup()
        await refreshMessages()

        engine.currentRoom = { [weak self] in self?.room }
        engine.isHost = { [weak self] in self?.isHost ?? false }
        engine.presentIDs = { [weak self] in self?.channel.presentUserIDs ?? [] }

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.channel.events { self.handle(event) }
        }
        startTicker()

        let me = PresenceMember(
            userId: profile.id, handle: profile.handle, avatar: profile.avatar,
            joinedAtMs: serverClock.now.epochSeconds * 1000)
        await channel.start(me: me)
        engine.start(clock: serverClock)

        loadState = .ready
    }

    func stop() async {
        eventTask?.cancel()
        tickTask?.cancel()
        engine.stop()
        serverClock.stop()
        playback.stop()
        await channel.stop()
        started = false
    }

    // MARK: - Actions

    func stepUp() async {
        try? await lineupService.stepUp(roomID: roomID)
        await refreshLineup()
    }

    func stepDown() async {
        try? await lineupService.stepDown(roomID: roomID)
        await refreshLineup()
    }

    func cue(_ track: Track) async {
        try? await lineupService.cue(roomID: roomID, track: track)
        await refreshLineup()
    }

    func vote(_ kind: VoteKind) async {
        guard let room, let round = room.roundId, let track = room.currentTrack else { return }
        try? await voteService.castVote(
            roomID: roomID, roundID: round, trackID: track.trackId,
            djID: room.currentDjId, voterID: profile.id, vote: kind)
        await refreshVotes()
        await refreshDJRating()
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await chatService.send(roomID: roomID, userID: profile.id, text: trimmed)
    }

    // MARK: - Realtime handling

    private func handle(_ event: RoomEvent) {
        switch event {
        case .roomUpdated(let room):
            apply(room: room)
        case .lineupChanged:
            Task { await refreshLineup() }
        case .votesChanged:
            Task { await refreshVotes(); await refreshDJRating() }
        case .messageInserted(let message):
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        case .presenceChanged:
            break  // audience is observed directly from the channel
        }
    }

    private func apply(room: Room) {
        self.room = room
        playback.update(room: room)
        if room.roundId != currentRoundID {
            currentRoundID = room.roundId
            votes = []
            djHotVotes = 0
            djTotalVotes = 0
            Task { await refreshVotes(); await refreshDJRating() }
        }
    }

    private func refreshLineup() async {
        if let updated = try? await lineupService.fetchLineup(roomID: roomID) { lineup = updated }
    }

    private func refreshVotes() async {
        guard let round = room?.roundId else { votes = []; return }
        if let updated = try? await voteService.fetchVotes(roundID: round) { votes = updated }
    }

    private func refreshMessages() async {
        if let recent = try? await chatService.fetchRecent(roomID: roomID) { messages = recent }
    }

    private func refreshDJRating() async {
        guard let dj = room?.currentDjId else { djHotVotes = 0; djTotalVotes = 0; return }
        if let all = try? await voteService.fetchVotesByDJ(roomID: roomID, djID: dj) {
            djTotalVotes = all.count
            djHotVotes = all.filter { $0.vote == .hot }.count
        }
    }

    private func startTicker() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick &+= 1
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func message(for error: Error) -> String {
        if let local = error as? LocalizedError, let desc = local.errorDescription { return desc }
        return "Something went wrong. Pull to retry."
    }
}
