//
//  Secrets.example.swift  →  copy to  Aux/Config/Secrets.swift
//  Aux
//
//  TEMPLATE. This file lives at the repo root (outside the app target) so it is
//  never compiled. Copy it to `Aux/Config/Secrets.swift` and paste in your real
//  Supabase credentials. `Aux/Config/Secrets.swift` is gitignored.
//
//      cp Secrets.example.swift Aux/Config/Secrets.swift
//
//  Find these in the Supabase dashboard:
//    Project Settings → API → "Project URL" and "Project API keys → anon / public".
//

import Foundation

enum Secrets {
    /// e.g. "https://abcdefghijklmno.supabase.co"
    static let supabaseURL = URL(string: "https://YOUR-PROJECT-ref.supabase.co")!

    /// The "anon" / public key. Safe to ship in a client; RLS protects your data.
    static let supabaseAnonKey = "YOUR-ANON-PUBLIC-KEY"

    /// True once real credentials have been pasted in.
    static var isConfigured: Bool {
        supabaseAnonKey != "YOUR-ANON-PUBLIC-KEY"
            && supabaseURL.host?.contains("YOUR-PROJECT-ref") == false
    }
}
