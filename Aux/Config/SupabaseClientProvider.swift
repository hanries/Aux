//
//  SupabaseClientProvider.swift
//  Aux
//
//  Single shared SupabaseClient, built from Secrets. The session is persisted
//  automatically by supabase-swift (Keychain), so anonymous users keep their
//  identity across launches.
//

import Foundation
import Supabase

/// Shared Supabase client for the whole app.
///
/// `nonisolated(unsafe)` opts this global out of the project's default-MainActor
/// isolation inference (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor). It's safe:
/// `SupabaseClient` is `Sendable` and we never reassign it.
nonisolated(unsafe) let supabase = SupabaseClient(
    supabaseURL: Secrets.supabaseURL,
    supabaseKey: Secrets.supabaseAnonKey,
    options: SupabaseClientOptions()
)
