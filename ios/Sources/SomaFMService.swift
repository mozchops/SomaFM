import Foundation

struct Station: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var description: String
    var genre: String
    var image: String
    var bitrate: Int
    var url: String
}

struct Track {
    var title: String
    var artist: String
}

enum SomaFMService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    static func fetchCatalog() async throws -> [Station] {
        let data = try await fetch(
            "https://api.somafm.com/channels.json",
            expectedHost: "api.somafm.com",
            byteLimit: 512 * 1024
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = root["channels"] as? [[String: Any]],
              !channels.isEmpty, channels.count <= 120 else {
            throw ServiceError.invalidCatalog
        }

        var stations: [Station] = []
        for startIndex in stride(from: 0, to: channels.count, by: 8) {
            let endIndex = min(startIndex + 8, channels.count)
            await withTaskGroup(of: Station?.self) { group in
                for channel in channels[startIndex..<endIndex] {
                    group.addTask { await makeStation(from: channel) }
                }
                for await station in group {
                    if let station { stations.append(station) }
                }
            }
        }
        return stations.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func fetchTrack(id: String) async throws -> Track {
        guard isValidChannelID(id) else { throw ServiceError.invalidCatalog }
        let data = try await fetch(
            "https://somafm.com/songs/\(id).json",
            expectedHost: "somafm.com",
            byteLimit: 64 * 1024
        )
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let first = (root?["songs"] as? [[String: Any]])?.first ?? [:]
        return Track(
            title: clean(first["title"] as? String, limit: 160),
            artist: clean(first["artist"] as? String, limit: 120)
        )
    }

    private static func makeStation(from channel: [String: Any]) async -> Station? {
        guard let id = channel["id"] as? String, isValidChannelID(id),
              let playlists = channel["playlists"] as? [[String: Any]], playlists.count <= 20 else {
            return nil
        }
        let eligible = playlists.compactMap { playlist -> (String, URL)? in
            guard let rawURL = playlist["url"] as? String,
                  let url = URL(string: rawURL),
                  url.scheme == "https", url.host == "api.somafm.com",
                  url.path.range(
                    of: "^/\(NSRegularExpression.escapedPattern(for: id))[0-9]*\\.pls$",
                    options: .regularExpression
                  ) != nil else { return nil }
            return ((playlist["quality"] as? String ?? "").lowercased(), url)
        }
        let preferred = eligible.filter { $0.0 == "highest" }
        let playlistsToTry = preferred.isEmpty ? eligible : preferred

        var streamURLs: [URL] = []
        for (_, playlistURL) in playlistsToTry {
            guard let data = try? await fetch(
                playlistURL.absoluteString,
                expectedHost: "api.somafm.com",
                byteLimit: 32 * 1024
            ), let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                guard line.lowercased().hasPrefix("file"),
                      let raw = line.split(separator: "=", maxSplits: 1).last,
                      let streamURL = URL(string: String(raw).trimmingCharacters(in: .whitespacesAndNewlines)),
                      isValidStreamURL(streamURL, channelID: id) else { continue }
                streamURLs.append(streamURL)
            }
        }

        var seenURLs: Set<String> = []
        let uniqueURLs = streamURLs.filter { seenURLs.insert($0.absoluteString).inserted }
        guard let bestURL = uniqueURLs.max(by: { bitrate($0) < bitrate($1) }),
              bitrate(bestURL) > 0 else { return nil }

        let rawTitle = clean(channel["title"] as? String, limit: 100)
        return Station(
            id: id,
            title: rawTitle.isEmpty ? id : rawTitle,
            description: clean(channel["description"] as? String, limit: 280),
            genre: clean(channel["genre"] as? String, limit: 60),
            image: validImage(channel["image"] as? String ?? ""),
            bitrate: bitrate(bestURL),
            url: bestURL.absoluteString
        )
    }

    private static func fetch(_ address: String, expectedHost: String, byteLimit: Int) async throws -> Data {
        guard let url = URL(string: address), url.scheme == "https", url.host == expectedHost else {
            throw ServiceError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("SomaFMiOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              response.url?.scheme == "https",
              response.url?.host == expectedHost,
              data.count <= byteLimit else { throw ServiceError.invalidResponse }
        return data
    }

    private static func isValidChannelID(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9][a-z0-9-]{0,47}$"#, options: .regularExpression) != nil
    }

    private static func isValidStreamURL(_ url: URL, channelID: String) -> Bool {
        guard url.scheme == "https", url.port == nil,
              url.host?.range(of: #"^ice[0-9]+\.somafm\.com$"#, options: .regularExpression) != nil else {
            return false
        }
        return url.path.range(
            of: "^/\(NSRegularExpression.escapedPattern(for: channelID))(?:-[a-z0-9]+)+$",
            options: .regularExpression
        ) != nil
    }

    private static func validImage(_ value: String) -> String {
        guard let url = URL(string: value), url.scheme == "https",
              url.host == "api.somafm.com",
              url.path.range(of: #"^/logos/120/[A-Za-z0-9-]+120\.(png|jpe?g|gif)$"#,
                             options: .regularExpression) != nil else { return "" }
        return value
    }

    private static func bitrate(_ url: URL) -> Int {
        guard let range = url.path.range(
            of: #"(?:-|/)([0-9]{2,3})-(?:mp3|aacp?|ogg|opus)$"#,
            options: .regularExpression
        ) ?? url.path.range(of: #"[0-9]{2,3}\.(?:mp3|aacp?|ogg|opus)$"#,
                            options: .regularExpression),
        let digits = url.path[range].range(of: #"[0-9]{2,3}"#, options: .regularExpression) else {
            return 0
        }
        return Int(url.path[digits]) ?? 0
    }

    private static func clean(_ value: String?, limit: Int) -> String {
        String((value ?? "").filter { $0 >= " " && $0 != "\u{7f}" }.prefix(limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ServiceError: LocalizedError {
        case invalidCatalog
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidCatalog: "SomaFM returned an invalid station catalog."
            case .invalidResponse: "SomaFM returned an invalid or oversized response."
            }
        }
    }
}
