//
//  UserProfile.swift
//  Aux
//

import Foundation

struct UserProfile: Codable, Identifiable, Hashable {
    let id: String
    let handle: String
    let avatar: String

    enum CodingKeys: String, CodingKey {
        case id, handle, avatar
    }
}

/// Upsert payload for the `users` table.
struct UserProfileUpsert: Encodable {
    let id: String
    let handle: String
    let avatar: String
}
