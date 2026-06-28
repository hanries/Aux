//
//  DMService.swift
//  Aux
//
//  1:1 DM threads + messages. Sends go through send_dm (membership + block
//  checked); reads are RLS-guarded to thread members.
//

import Foundation
import Supabase
import PostgREST

struct DMService {
    /// Find-or-create the 1:1 thread with `other`, returning its id.
    func openThread(with other: String) async throws -> String {
        try await supabase
            .rpc("find_or_create_dm", params: OtherUserParam(p_other: other))
            .execute()
            .value
    }

    func send(dmID: String, text: String) async throws {
        try await supabase
            .rpc("send_dm", params: SendDMParams(p_dm_id: dmID, p_text: text))
            .execute()
    }

    func markRead(dmID: String) async throws {
        try await supabase.rpc("mark_dm_read", params: DMIDParam(p_dm_id: dmID)).execute()
    }

    func threads() async throws -> [DMThread] {
        try await supabase.rpc("my_dms").execute().value
    }

    func messages(dmID: String) async throws -> [DMMessage] {
        try await supabase
            .from("dm_messages")
            .select()
            .eq("dm_id", value: dmID)
            .order("created_ms", ascending: true)
            .execute()
            .value
    }
}

struct SendDMParams: Encodable { let p_dm_id: String; let p_text: String }
struct DMIDParam: Encodable { let p_dm_id: String }
