//
//  SearchView.swift
//  Aux
//
//  iTunes search → cue a 30s pick for your turn on the decks.
//

import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var results: [Track] = []
    private(set) var isLoading = false
    private(set) var errorText: String?

    private let service = ITunesSearchService()
    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        let term = query
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))   // debounce
            guard !Task.isCancelled else { return }
            await run(term)
        }
    }

    private func run(_ term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; errorText = nil; return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            results = try await service.search(trimmed)
        } catch {
            results = []
            errorText = (error as? LocalizedError)?.errorDescription ?? "Search failed."
        }
    }
}

struct SearchView: View {
    let vm: RoomViewModel

    @State private var model = SearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                content
            }
            .navigationTitle("Cue a track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $model.query, prompt: "Songs, artists…")
            .onChange(of: model.query) { _, _ in model.search() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            LoadingView(label: "Searching…")
        } else if let error = model.errorText {
            ErrorView(message: error)
        } else if model.results.isEmpty {
            ContentUnavailableView(
                "Find your pick",
                systemImage: "magnifyingglass",
                description: Text("Search iTunes for a track to cue when your turn comes."))
        } else {
            List(model.results) { track in
                Button {
                    Task {
                        await vm.cueSet(track)
                        dismiss()
                    }
                } label: {
                    TrackRow(track: track)
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.artworkURLSmall) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.trackName).font(.subheadline).lineLimit(1)
                Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
    }
}
