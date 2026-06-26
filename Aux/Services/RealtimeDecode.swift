//
//  RealtimeDecode.swift
//  Aux
//
//  Realtime postgres_changes deliver a row as `[String: AnyJSON]`. We round-trip
//  it through JSON to decode into our Codable models — one path for every table.
//

import Foundation
import Supabase

enum RealtimeDecode {
    static func decode<T: Decodable>(_ type: T.Type, from record: [String: AnyJSON]) -> T? {
        do {
            let data = try JSONEncoder().encode(record)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}
