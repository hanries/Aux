//
//  ConnectionRefs.swift
//  Aux
//
//  Small Identifiable wrappers for sheet presentation.
//

import Foundation

struct UserRef: Identifiable, Hashable { let id: String }

struct DMTarget: Identifiable, Hashable {
    let dmID: String
    let otherID: String
    let otherHandle: String
    let otherAvatar: String
    var id: String { dmID }
}
