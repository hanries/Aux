//
//  DMThreadView.swift
//  Aux
//
//  A 1:1 DM thread — realtime messages, send, and mark-read. Pushed from the
//  inbox or presented (wrapped in a NavigationStack) from a profile / twin card.
//

import SwiftUI

@MainActor
@Observable
final class DMThreadViewModel {
    let dmID: String
    let meID: String
    private(set) var messages: [DMMessage] = []

    private let service = DMService()
    private let channel: DMChannel
    private var eventTask: Task<Void, Never>?
    private var started = false

    init(dmID: String, meID: String) {
        self.dmID = dmID
        self.meID = meID
        self.channel = DMChannel(dmID: dmID)
    }

    func start() async {
        guard !started else { return }
        started = true
        messages = (try? await service.messages(dmID: dmID)) ?? []
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.channel.events {
                if !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                }
                try? await self.service.markRead(dmID: self.dmID)
            }
        }
        await channel.start()
        try? await service.markRead(dmID: dmID)
    }

    func stop() async {
        eventTask?.cancel()
        await channel.stop()
        try? await service.markRead(dmID: dmID)
        started = false
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await service.send(dmID: dmID, text: trimmed)
    }
}

struct DMThreadView: View {
    let profile: UserProfile
    let dmID: String
    let otherID: String
    let otherHandle: String
    let otherAvatar: String

    @State private var vm: DMThreadViewModel
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    init(profile: UserProfile, dmID: String, otherID: String, otherHandle: String, otherAvatar: String) {
        self.profile = profile
        self.dmID = dmID
        self.otherID = otherID
        self.otherHandle = otherHandle
        self.otherAvatar = otherAvatar
        _vm = State(initialValue: DMThreadViewModel(dmID: dmID, meID: profile.id))
    }

    var body: some View {
        ZStack {
            NightBackground()
            VStack(spacing: 0) {
                messages
                inputBar
            }
        }
        .navigationTitle(otherHandle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start() }
        .onDisappear { Task { await vm.stop() } }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.messages) { message in
                        bubble(message).id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ message: DMMessage) -> some View {
        let mine = message.senderId == profile.id
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    mine ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 16))
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message @\(otherHandle)…", text: $draft)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await vm.send(text) }
    }
}
