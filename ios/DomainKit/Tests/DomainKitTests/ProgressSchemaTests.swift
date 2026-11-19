// TKL-856: SeriesProgressRecord and ReadingPlanProgressRecord shipped in the
// App Store 1.0 store (build 2, Aug 2026). Dropping a model from a container
// that already exists on a device is a migration, so they stay in the schema
// as retired tables until a versioned migration removes them.
import Testing
import SwiftData
@testable import DomainKit

@Suite("progressSchema")
struct ProgressSchemaTests {
    @Test("keeps the shipped, retired devotion tables so existing stores still open")
    func keepsShippedModels() {
        let names = Set(progressSchema.entities.map(\.name))
        #expect(names.isSuperset(of: [
            "LocalCatechismTrack", "ProgressSettings",
            "SeriesProgressRecord", "ReadingPlanProgressRecord",
        ]))
    }

    @Test("a store opens with the schema")
    func opens() throws {
        let config = ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)
        _ = try ModelContainer(for: progressSchema, configurations: [config])
    }
}
