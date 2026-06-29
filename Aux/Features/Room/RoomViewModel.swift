//
//  RoomViewModel.swift
//  Aux
//
//  The room's brain (rebuild). People-first: the crowd is the hero, the audience
//  reacts (live + attributed), and a single DJ holds the decks for a SET of clips
//  by possession. No hot/skip, no vote/reveal phase. Owns the clock, realtime
//  channel, rotation engine and playback; exposes derived state for thin views.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoomViewModel {

    enum LoadState: Equatable { case loading, ready, failed(String) }

    /// What the room is doing right now (no voting/reveal phases anymore).
    enum RoundStage { case idle, playing, picking }

    struct Spark: Identifiable, Equatable {
        let id = UUID()
        let userID: String
        let handle: String
        let avatar: String
    }

    let profile: UserProfile
    let roomID: String
    let playback = PlaybackController()
    let serverClock = ServerClock.shared

    private let channel: RoomChannel
    private let engine: RoomEngine
    private let auth = AuthService()
    private let roomService = RoomService()
    private let lineupService = LineupService()
    private let reactionService = ReactionService()
    private let chatService = ChatService()
    private let tasteTwinService = TasteTwinService()
    private let presenceService = PresenceService()
    private let blockService = BlockService()

    /// Durable identity (handle/avatar) from the `users` table.
    private(set) var profileCache: [String: UserProfile] = [:]

    // Observable state
    var loadState: LoadState = .loading
    private(set) var room: Room?
    private(set) var lineup: [LineupEntry] = []
    private(set) var messages: [ChatMessage] = []
    private(set) var reactions: [Reaction] = []        // recent, for the live overlay
    private(set) var myLoves: Set<String> = []         // track ids I've loved
    private(set) var tasteTwins: [TasteTwin] = []
    private(set) var blockedIDs: Set<String> = []
    private(set) var spark: Spark?                     // in-moment taste-twin spark
    private(set) var waveToast: String?                // "@x waved at you"
    var tick = 0

    private var started = false
    private var eventTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var sparkTask: Task<Void, Never>?
    private var waveTask: Task<Void, Never>?
    private var currentRoundID: String?
    private var lastTwinFetch = Date.distantPast
    private var sparkedUserIDs: Set<String> = []

    init(profile: UserProfile, roomID: String, initialRoom: Room? = nil) {
        self.profile = profile
        self.roomID = roomID
        self.room = initialRoom
        self.channel = RoomChannel(roomID: roomID)
        self.engine = RoomEngine(roomID: roomID)
    }

    // MARK: - Derived state

    enum Role { case onDeck, inLine, audience }

    var audience: [PresenceMember] { channel.members.filter { !blockedIDs.contains($0.userId) } }
    var amOnDeck: Bool { room?.currentDjId == profile.id }
    var amInLineup: Bool { lineup.contains { $0.userId == profile.id } }
    var myCuedSet: [Track] { lineup.first { $0.userId == profile.id }?.set ?? [] }
    var onDeckTrack: Track? { room?.currentTrack }

    var isLeader: Bool {
        guard let room else { return false }
        if let dj = room.currentDjId, channel.presentUserIDs.contains(dj) {
            return dj == profile.id
        }
        return channel.longestPresentID == profile.id
    }

    var myRole: Role {
        if amOnDeck { return .onDeck }
        if amInLineup { return .inLine }
        return .audience
    }

    var myLinePosition: Int? {
        guard let idx = waitingLineup.firstIndex(where: { $0.userId == profile.id }) else { return nil }
        return idx + 1
    }

    var upNextName: String? {
        guard let next = waitingLineup.first else { return nil }
        return displayMember(next.userId).handle
    }

    var onDeckName: String {
        guard let dj = room?.currentDjId else { return "Auto-DJ" }
        return displayMember(dj).handle
    }
    var onDeckAvatar: String {
        guard let dj = room?.currentDjId else { return "🤖" }
        return displayMember(dj).avatar
    }

    var waitingLineup: [LineupEntry] { lineup.filter { $0.userId != room?.currentDjId } }

    var roundStage: RoundStage {
        switch room?.phase {
        case .picking: return .picking
        case .playing: return .playing
        default: return .idle
        }
    }

    var progress: Double {
        guard RoomConfig.clipDuration > 0 else { return 0 }
        return min(1, max(0, playback.positionSeconds / RoomConfig.clipDuration))
    }

    /// Did I love the track that's playing right now?
    var iLoveCurrent: Bool {
        guard let id = room?.currentTrack?.trackId else { return false }
        return myLoves.contains(id)
    }

    /// The current DJ's warmth = love reactions on their picks (this session window).
    var djWarmth: Int {
        guard let dj = room?.currentDjId else { return 0 }
        return reactions.filter { $0.djId == dj && $0.type == .love }.count
    }

    /// Recent reactions to float in the live overlay (most recent last).
    var recentReactions: [Reaction] { reactions.suffix(24) }

    var pickingSecondsLeft: Int? {
        _ = tick
        guard room?.phase == .picking, let deadline = room?.phaseDeadline else { return nil }
        return max(0, Int(serverClock.now.seconds(until: deadline).rounded(.up)))
    }

    func displayMember(_ userID: String) -> (handle: String, avatar: String) {
        if userID == profile.id { return (profile.handle, profile.avatar) }
        if let cached = profileCache[userID] { return (cached.handle, cached.avatar) }
        if let m = channel.members.first(where: { $0.userId == userID }) { return (m.handle, m.avatar) }
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
        if let recent = try? await reactionService.fetchRecent(roomID: roomID) {
            reactions = recent.reversed()      // oldest → newest
        }

        engine.currentRoom = { [weak self] in self?.room }
        engine.isLeader = { [weak self] in self?.isLeader ?? false }
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

        blockedIDs = (try? await blockService.blockedIDs()) ?? []
        try? await presenceService.set(roomID: roomID)
        startPresenceHeartbeat()

        loadState = .ready
    }

    func stop() async {
        eventTask?.cancel(); tickTask?.cancel(); presenceTask?.cancel()
        sparkTask?.cancel(); waveTask?.cancel()
        engine.stop()
        playback.stop()
        await channel.stop()
        try? await presenceService.set(roomID: nil)
        started = false
    }

    func enterBackground() async {
        guard started else { return }
        presenceTask?.cancel()
        engine.stop()
        playback.suspend()
        await channel.untrack()
        try? await presenceService.set(roomID: nil)
    }

    func enterForeground() async {
        guard started else { return }
        await serverClock.calibrate()
        await channel.retrack()
        if let fresh = try? await roomService.fetchRoom(id: roomID) { apply(room: fresh) }
        playback.resume()
        engine.start(clock: serverClock)
        try? await presenceService.set(roomID: roomID)
        startPresenceHeartbeat()
    }

    private func startPresenceHeartbeat() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RoomConfig.presenceHeartbeat))
                guard let self else { return }
                try? await self.presenceService.set(roomID: self.roomID)
            }
        }
    }

    func applyBlocked(_ ids: Set<String>) { blockedIDs = ids }

    // MARK: - Actions

    func stepUp() async {
        try? await lineupService.stepUp(roomID: roomID)
        await refreshLineup()
    }

    func stepDown() async {
        try? await lineupService.stepDown(roomID: roomID)
        await refreshLineup()
    }

    func cueSet(_ track: Track) async {
        try? await lineupService.cueSet(roomID: roomID, track: track)
        await refreshLineup()
    }

    /// Send a reaction. `love` toggles my taste signal + may fire a spark.
    func react(_ type: ReactionType, target: String? = nil) async {
        guard let room else { return }
        let track = room.currentTrack
        if type == .love, let tid = track?.trackId {
            myLoves.insert(tid)
            checkSparkForMyLove(trackID: tid)
        }
        try? await reactionService.react(
            roomID: roomID, roundID: room.roundId, trackID: track?.trackId,
            djID: room.currentDjId, userID: profile.id, type: type,
            targetUserID: target, track: type == .love ? track : nil)
    }

    func wave(at userID: String) async {
        await react(.wave, target: userID)
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await chatService.send(roomID: roomID, userID: profile.id, text: trimmed)
    }

    func refreshTasteTwins(force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastTwinFetch) < 5 { return }
        lastTwinFetch = Date()
        if let twins = try? await tasteTwinService.fetch(roomID: roomID) { tasteTwins = twins }
    }

    // MARK: - Realtime handling

    private func handle(_ event: RoomEvent) {
        switch event {
        case .roomUpdated(let room):
            apply(room: room)
        case .lineupChanged:
            Task { await refreshLineup() }
        case .reaction(let reaction):
            ingest(reaction)
        case .messageInserted(let message):
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
            Task { await ensureProfiles([message.userId]) }
        case .presenceChanged:
            for member in channel.members where profileCache[member.userId] == nil {
                profileCache[member.userId] = UserProfile(
                    id: member.userId, handle: member.handle, avatar: member.avatar)
            }
        }
    }

    private func ingest(_ reaction: Reaction) {
        if !reactions.contains(where: { $0.id == reaction.id }) {
            reactions.append(reaction)
            if reactions.count > 60 { reactions.removeFirst(reactions.count - 60) }
        }
        Task { await ensureProfiles([reaction.userId]) }

        // Directed wave at me → toast.
        if reaction.type == .wave, reaction.targetUserId == profile.id, reaction.userId != profile.id {
            showWave(from: reaction.userId)
        }
        // Someone loved a track I also loved → spark.
        if reaction.type == .love, reaction.userId != profile.id,
           let tid = reaction.trackId, myLoves.contains(tid) {
            fireSpark(with: reaction.userId)
        }
    }

    /// When I love a track, see if a present stranger already loved it → spark.
    private func checkSparkForMyLove(trackID: String) {
        if let other = reactions.first(where: {
            $0.type == .love && $0.userId != profile.id && $0.trackId == trackID
        }) {
            fireSpark(with: other.userId)
        }
    }

    private func fireSpark(with userID: String) {
        guard !sparkedUserIDs.contains(userID), !blockedIDs.contains(userID) else { return }
        sparkedUserIDs.insert(userID)
        let info = displayMember(userID)
        spark = Spark(userID: userID, handle: info.handle, avatar: info.avatar)
        sparkTask?.cancel()
        sparkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.spark = nil
        }
    }

    func dismissSpark() { spark = nil; sparkTask?.cancel() }

    private func showWave(from userID: String) {
        waveToast = "\(displayMember(userID).handle) waved at you 👋"
        waveTask?.cancel()
        waveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.waveToast = nil
        }
    }

    private func apply(room: Room) {
        self.room = room
        playback.update(room: room)
        if let dj = room.currentDjId { Task { await ensureProfiles([dj]) } }
        currentRoundID = room.roundId
    }

    private func refreshLineup() async {
        if let updated = try? await lineupService.fetchLineup(roomID: roomID) { lineup = updated }
        await ensureProfiles(lineup.map(\.userId))
    }

    private func refreshMessages() async {
        if let recent = try? await chatService.fetchRecent(roomID: roomID) { messages = recent }
        await ensureProfiles(messages.map(\.userId))
    }

    private func ensureProfiles(_ ids: [String]) async {
        let missing = Set(ids).subtracting(profileCache.keys).subtracting([profile.id])
            .filter { !$0.isEmpty }
        guard !missing.isEmpty else { return }
        if let fetched = try? await auth.fetchProfiles(ids: Array(missing)) {
            for profile in fetched { profileCache[profile.id] = profile }
        }
    }

    private func startTicker() {
        tickTask = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.tick &+= 1
                n += 1
                if n % 20 == 0 { await self.refreshTasteTwins() }   // ~every 10s
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func message(for error: Error) -> String {
        if let local = error as? LocalizedError, let desc = local.errorDescription { return desc }
        return "Something went wrong. Pull to retry."
    }
}
