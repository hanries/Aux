//
//  ChatView.swift
//  Aux
//
//  Realtime room chat. Messages + presence-resolved sender info live on the
//  RoomViewModel, so this view just renders + sends.
//

import SwiftUI

struct ChatView: View {
    let vm: RoomViewModel

    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                VStack(spacing: 0) {
                    messages
                    inputBar
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { message in
                        messageRow(message)
                            .id(message.id)
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

    private func messageRow(_ message: ChatMessage) -> some View {
        let info = vm.displayMember(message.userId)
        return HStack(alignment: .top, spacing: 10) {
            AvatarView(emoji: info.avatar, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.handle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(message.text).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Say something…", text: $draft)
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
