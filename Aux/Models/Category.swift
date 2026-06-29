//
//  Category.swift
//  Aux
//
//  A genre/mood that holds one or more room instances. The browse structure +
//  cold-start funnel + aesthetic anchor (themed by `genre`).
//

import Foundation

struct Category: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let genre: String
    let sort: Int
}
