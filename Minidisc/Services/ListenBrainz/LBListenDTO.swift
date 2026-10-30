import Foundation

/// One listen from `GET /1/user/{user}/listens` (#16), trimmed to what Wrapped needs.
/// Codable so a month of listens can be cached on disk as received.
nonisolated struct LBListen: Codable, Sendable, Equatable {
    let listenedAt: Int
    let trackName: String
    let artistName: String
    let releaseName: String?
    /// Milliseconds, when the submitting player sent it.
    let durationMs: Int?
    let recordingMBID: String?

    enum CodingKeys: String, CodingKey {
        case listenedAt = "listened_at"
        case trackMetadata = "track_metadata"
        // Flattened form used by the on-disk cache.
        case trackName, artistName, releaseName, durationMs, recordingMBID
    }

    private struct TrackMetadata: Decodable {
        let artist_name: String
        let track_name: String
        let release_name: String?
        let additional_info: AdditionalInfo?
        let mbid_mapping: MBIDMapping?
    }

    private struct AdditionalInfo: Decodable {
        let duration_ms: Int?
        let duration: Int?
        let recording_mbid: String?
    }

    private struct MBIDMapping: Decodable {
        let recording_mbid: String?
    }

    init(listenedAt: Int, trackName: String, artistName: String, releaseName: String?,
         durationMs: Int?, recordingMBID: String?) {
        self.listenedAt = listenedAt
        self.trackName = trackName
        self.artistName = artistName
        self.releaseName = releaseName
        self.durationMs = durationMs
        self.recordingMBID = recordingMBID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listenedAt = try c.decode(Int.self, forKey: .listenedAt)
        if let meta = try c.decodeIfPresent(TrackMetadata.self, forKey: .trackMetadata) {
            // The API's shape. MusicBrainz' own mapping is preferred over what the player sent.
            trackName = meta.track_name
            artistName = meta.artist_name
            releaseName = meta.release_name
            durationMs = meta.additional_info?.duration_ms ?? meta.additional_info?.duration.map { $0 * 1000 }
            recordingMBID = meta.mbid_mapping?.recording_mbid ?? meta.additional_info?.recording_mbid
        } else {
            trackName = try c.decode(String.self, forKey: .trackName)
            artistName = try c.decode(String.self, forKey: .artistName)
            releaseName = try c.decodeIfPresent(String.self, forKey: .releaseName)
            durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
            recordingMBID = try c.decodeIfPresent(String.self, forKey: .recordingMBID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listenedAt, forKey: .listenedAt)
        try c.encode(trackName, forKey: .trackName)
        try c.encode(artistName, forKey: .artistName)
        try c.encodeIfPresent(releaseName, forKey: .releaseName)
        try c.encodeIfPresent(durationMs, forKey: .durationMs)
        try c.encodeIfPresent(recordingMBID, forKey: .recordingMBID)
    }
}

nonisolated struct LBListensResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let listens: [LBListen]
    }
    let payload: Payload
}
