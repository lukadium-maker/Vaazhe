import Foundation
import SwiftData

@Model final class PracticeSessionRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var payload: Data
    var copiedBaseline: Bool
    var sequence: Int

    init(id: UUID, date: Date, payload: Data, sequence: Int, copiedBaseline: Bool = false) {
        self.id = id
        self.date = date
        self.payload = payload
        self.copiedBaseline = copiedBaseline
        self.sequence = sequence
    }

    var result: PracticeResult? { try? JSONDecoder().decode(PracticeResult.self, from: payload) }
}

@MainActor enum PracticeStore {
    static func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([PracticeSessionRecord.self])
        let configuration = if let url {
            ModelConfiguration("Playground", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration("Playground", schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func results(in context: ModelContext) throws -> [PracticeResult] {
        try context.fetch(FetchDescriptor<PracticeSessionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse),
                                                                        SortDescriptor(\.sequence, order: .reverse)]))
            .compactMap(\.result)
    }

    static func save(_ result: PracticeResult, in context: ModelContext) throws {
        let id = result.id
        let query = FetchDescriptor<PracticeSessionRecord>(predicate: #Predicate { $0.id == id })
        guard try context.fetchCount(query) == 0 else { return }
        let payload = try JSONEncoder().encode(result)
        var latest = FetchDescriptor<PracticeSessionRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        latest.fetchLimit = 1
        let sequence = (try context.fetch(latest).first?.sequence ?? 0) + 1
        context.insert(PracticeSessionRecord(id: id, date: result.date, payload: payload, sequence: sequence))
        try ReviewStore.save(context)
    }
}
