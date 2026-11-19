import Foundation

/// The website's Supabase project, read from Info.plist (`SupabaseURL`,
/// `SupabasePublishableKey`, filled from the SUPABASE_* build settings in
/// project.yml). The publishable key is public by design; RLS protects data.
/// The service role key must never appear here.
struct SupabaseConfig: Equatable, Sendable {
    let url: URL
    let publishableKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        from(info: bundle.infoDictionary ?? [:])
    }

    static func from(info: [String: Any]) -> SupabaseConfig? {
        guard
            let rawURL = info["SupabaseURL"] as? String,
            let url = URL(string: rawURL), url.scheme == "https", url.host != nil,
            let key = info["SupabasePublishableKey"] as? String,
            // Unexpanded "$(…)" means the build setting is missing.
            !key.isEmpty, !key.hasPrefix("$(")
        else { return nil }
        return SupabaseConfig(url: url, publishableKey: key)
    }
}
