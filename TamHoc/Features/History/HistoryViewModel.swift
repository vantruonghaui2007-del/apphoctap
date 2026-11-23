import Foundation
import StudyCore

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var records: [SessionRecord] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var unsupportedSchemaCount: Int = 0
    @Published public private(set) var quarantinedCount: Int = 0

    private let repository: SessionRepository

    public init(repository: SessionRepository) {
        self.repository = repository
    }

    public func load() async {
        errorMessage = nil
        do {
            let result = try await repository.loadAll()
            self.records = result.records
            self.unsupportedSchemaCount = result.unsupportedSchemaFiles.count
            self.quarantinedCount = result.quarantinedIDs.count
        } catch {
            self.errorMessage = "Không thể tải lịch sử phiên học."
        }
    }

    public func delete(id: UUID) async {
        do {
            try await repository.delete(id: id)
            records.removeAll { $0.id == id }
        } catch {
            errorMessage = "Không thể xóa bản ghi phiên học."
        }
    }

    public func deleteAll() async {
        for record in records {
            do {
                try await repository.delete(id: record.id)
            } catch {
                errorMessage = "Không thể xóa toàn bộ lịch sử."
                await load()
                return
            }
        }
        records.removeAll()
    }
}
