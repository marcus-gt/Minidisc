import Foundation
import Testing
import SwiftSonic
@testable import Minidisc

private func album(_ id: String, labels: [String], created: String? = nil, coverArt: String? = nil) throws -> AlbumID3 {
    var json: [String: Any] = ["id": id, "name": id, "songCount": 1, "duration": 60,
                               "recordLabels": labels.map { ["name": $0] }]
    if let created { json["created"] = created }
    if let coverArt { json["coverArt"] = coverArt }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(AlbumID3.self, from: JSONSerialization.data(withJSONObject: json))
}

private final class LabelLibraryStub: RecordLabelBrowsing, @unchecked Sendable {
    var result: Result<[RecordLabelSummary]?, any Error>
    init(_ result: Result<[RecordLabelSummary]?, any Error>) { self.result = result }
    func recordLabels() async throws -> [RecordLabelSummary]? { try result.get() }
}

@Suite("Record label list") @MainActor
struct RecordLabelListTests {
    @Test func summaries_variantSpellings_groupIntoOneLabelWithNewestSpellingAndCover() throws {
        let albums = [
            try album("old", labels: ["warp records"], created: "2020-01-01T00:00:00Z", coverArt: "c-old"),
            try album("new", labels: ["Warp Records"], created: "2024-01-01T00:00:00Z", coverArt: "c-new"),
            try album("ecm", labels: ["ECM"], created: "2022-01-01T00:00:00Z"),
        ]

        let labels = RecordLabelSummary.summaries(from: albums)

        #expect(labels.map(\.name) == ["ECM", "Warp Records"])
        #expect(labels[1].albumCount == 2)
        #expect(labels[1].coverArtId == "c-new")
        #expect(labels[0].coverArtId == "ecm", "Falls back to the album id when there is no cover id.")
    }

    @Test func summaries_blankAndRepeatedLabels_areIgnoredPerAlbum() throws {
        let albums = [try album("a", labels: ["  ", "Stones Throw", "stones throw"])]

        let labels = RecordLabelSummary.summaries(from: albums)

        #expect(labels.map(\.name) == ["Stones Throw"])
        #expect(labels.first?.albumCount == 1)
    }

    @Test func load_indexIncomplete_waitsForIndex() async {
        let vm = RecordLabelListViewModel(library: LabelLibraryStub(.success(nil)))

        await vm.load()

        #expect(vm.state == .waitingForIndex)
    }

    @Test func load_labels_loaded() async {
        let label = RecordLabelSummary(name: "Blue Note", albumCount: 3, coverArtId: nil)
        let vm = RecordLabelListViewModel(library: LabelLibraryStub(.success([label])))

        await vm.load()

        #expect(vm.state == .loaded)
        #expect(vm.labels == [label])
    }

    @Test func load_failure_mapsToUserFacingError() async {
        let vm = RecordLabelListViewModel(library: LabelLibraryStub(.failure(URLError(.notConnectedToInternet))))

        await vm.load()

        #expect(vm.state == .failed(.noNetwork))
    }
}
