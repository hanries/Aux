//
//  CategoryService.swift
//  Aux
//
//  Categories + the join funnel. `join_category` routes a newcomer to the best
//  room instance (fullest with space, reuse idle, else create "<Category> N").
//

import Foundation
import Supabase
import PostgREST

struct CategoryService {
    func fetchCategories() async throws -> [Category] {
        try await supabase
            .from("categories")
            .select()
            .order("sort", ascending: true)
            .execute()
            .value
    }

    /// Returns the room id to join for this category.
    func joinCategory(_ categoryID: String) async throws -> String {
        try await supabase
            .rpc("join_category", params: CategoryIDParam(p_category_id: categoryID))
            .execute()
            .value
    }
}

struct CategoryIDParam: Encodable { let p_category_id: String }
