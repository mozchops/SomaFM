import AVFoundation
import Foundation
import Observation

struct Station: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var description: String
    var genre: String
    var image: String
    var bitrate: Int
    var url: String
}

struct TrackEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var station: String
    var title: String
    var artist: String
    var playedAt: Date

    var display: String { title + (artist.isEmpty ? "" : " \u{2014} \(artist)") }
}

private struct SavedConfiguration: Codable {
    var version = 1
    var stations: [Station] = []
    var favorites: [Station] = []
    var favoriteSort = "name"
    var playTimes: [String: Int] = [:]
    var volume = 1.0
    var autoPlay: Bool?
    var showTrack: Bool?
    var recentTracks: [TrackEntry]?
    var lastStation: Station?
}

@Observable @MainActor
final class SomaFMModel {
    private(set) var stations: [Station] = []
    private(set) var currentStation: Station? {
        didSet {
            onStatusChanged?()
            onNowPlayingChanged?()
        }
    }
    private(set) var isPlaying = false {
        didSet {
            onStatusChanged?()
            onNowPlayingChanged?()
            updateStreamHealth()
        }
    }
    private(set) var playbackStopped = true {
        didSet {
            updateStreamHealth()
            onNowPlayingChanged?()
        }
    }
    private(set) var isLoading = false
    private(set) var trackTitle = "" {
        didSet { onNowPlayingChanged?() }
    }
    private(set) var trackArtist = "" {
        didSet { onNowPlayingChanged?() }
    }
    private(set) var streamHealth: StreamHealth = .idle
    private(set) var message = ""
    private(set) var warning = ""
    private(set) var level = 0.0 {
        didSet { onLevelChanged?() }
    }
    var onLevelChanged: (() -> Void)?
    var onStatusChanged: (() -> Void)?
    var onNowPlayingChanged: (() -> Void)?
    var searchText = ""
    var autoPlay = false {
        didSet { saveConfiguration() }
    }
    var showTrack = false {
        didSet {
            saveConfiguration()
            onStatusChanged?()
        }
    }
    private(set) var recentTracks: [TrackEntry] = []
    private(set) var sleepMinutes = 0
    private(set) var sleepDeadline: Date?
    private var sleepTask: Task<Void, Never>?
    var volume: Double = 1 {
        didSet {
            player.volume = Float(volume)
            saveConfiguration()
        }
    }
    var favoriteSort = "name" {
        didSet { saveConfiguration() }
    }
    private(set) var favoriteIDs: Set<String> = []
    private(set) var playTimes: [String: Int] = [:]

    private let player = AVPlayer()
    private var itemObservation: NSKeyValueObservation?
    private var playbackFailureObserver: NSObjectProtocol?
    private var playbackRequestID = UUID()
    private var trackTask: Task<Void, Never>?
    private var playTimeTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private var levelTap: LevelTap?
    private var playerStatusObservation: NSKeyValueObservation?
    private var lastTrackKey: String?
    private var savedFavorites: [Station] = []
    private let configURL: URL
    private var isLoadingConfiguration = true

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SomaFMMinimal", isDirectory: true)
        configURL = support.appendingPathComponent("stations.json")
        if !FileManager.default.fileExists(atPath: configURL.path) {
            let old = support.deletingLastPathComponent()
                .appendingPathComponent("SomaFM/stations.json")
            if FileManager.default.fileExists(atPath: old.path) {
                try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: old, to: configURL)
            }
        }
        loadConfiguration()
        player.volume = Float(volume)
        player.actionAtItemEnd = .pause
        playerStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateStreamHealth()
            }
        }
    }

    var statusLabel: String {
        if streamHealth == .offline { return "Playback failed \u{00B7} click Play to retry" }
        guard currentStation != nil else { return "Select a station below" }
        if playbackStopped { return "Stopped \u{00B7} right-click to play" }
        if streamHealth == .connecting { return "Connecting to stream\u{2026}" }
        if streamHealth == .buffering { return "Buffering\u{2026}" }
        return isPlaying ? "Playing \u{00B7} right-click to pause" : "Paused \u{00B7} right-click to resume"
    }

    var trackLabel: String {
        trackTitle.isEmpty ? "" : trackTitle + (trackArtist.isEmpty ? "" : " \u{2014} \(trackArtist)")
    }

    func cycleSleepTimer() {
        let choices = [0, 15, 30, 60, 90]
        sleepTask?.cancel()
        sleepMinutes = choices[((choices.firstIndex(of: sleepMinutes) ?? 0) + 1) % choices.count]
        guard sleepMinutes > 0 else { sleepDeadline = nil; return }
        let minutes = sleepMinutes
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task {
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            stopPlayback()
        }
    }

    func startIfAutoPlay() {
        if autoPlay, let station = currentStation, !isPlaying { play(station) }
    }

    var filteredStations: [Station] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = stations.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.genre.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
        }
        let favorites = matches.filter { favoriteIDs.contains($0.id) }
        let others = matches.filter { !favoriteIDs.contains($0.id) }
        let alphabetical: (Station, Station) -> Bool = {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let sortedFavorites: [Station]
        if favoriteSort == "time" {
            sortedFavorites = favorites.sorted {
                let left = playTimes[$0.id, default: 0]
                let right = playTimes[$1.id, default: 0]
                return left == right ? alphabetical($0, $1) : left > right
            }
        } else {
            sortedFavorites = favorites.sorted(by: alphabetical)
        }
        return sortedFavorites + others.sorted(by: alphabetical)
    }

    func toggleFavorite(_ station: Station) {
        if favoriteIDs.contains(station.id) {
            favoriteIDs.remove(station.id)
        } else {
            favoriteIDs.insert(station.id)
            savedFavorites.removeAll { $0.id == station.id }
            savedFavorites.append(station)
        }
        saveConfiguration()
    }

    func toggleFavoriteSort() {
        favoriteSort = favoriteSort == "time" ? "name" : "time"
    }

    func resetListeningTimes() {
        recordPlayTime()
        playTimes.removeAll()
        saveConfiguration()
    }

    func validateStreams() {
        guard !isLoading else { return }
        isLoading = true
        message = ""
        warning = ""
        Task {
            do {
                let result = try await SomaFMService.fetchCatalog()
                warning = result.skipped > 0 ? "Some streams could not be checked and were omitted." : ""
                guard !result.stations.isEmpty else {
                    message = "No verified streams are available right now."
                    isLoading = false
                    return
                }
                stations = result.stations
                if let currentStation {
                    self.currentStation = stations.first { $0.id == currentStation.id } ?? currentStation
                }
                for station in stations where favoriteIDs.contains(station.id) {
                    savedFavorites.removeAll { $0.id == station.id }
                    savedFavorites.append(station)
                }
                saveConfiguration()
            } catch {
                message = "Could not check SomaFM streams: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func play(_ station: Station) {
        recordPlayTime()
        let requestID = UUID()
        playbackRequestID = requestID
        trackTask?.cancel()
        playTimeTask?.cancel()
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
            self.playbackFailureObserver = nil
        }
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        playbackStartedAt = nil
        currentStation = station
        saveConfiguration()
        playbackStopped = false
        streamHealth = .connecting
        lastTrackKey = nil
        trackTitle = ""
        trackArtist = ""
        message = ""
        levelTap = nil
        level = 0
        let item = AVPlayerItem(url: URL(string: station.url)!)
        Task {
            do {
                let audioTracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard playbackRequestID == requestID else { return }
                if let audioTrack = audioTracks.first {
                    let meter = try LevelTap.create { [weak self] value in
                        DispatchQueue.main.async {
                            guard let self, self.playbackRequestID == requestID, self.isPlaying else { return }
                            self.level = value
                        }
                    }
                    let input = AVMutableAudioMixInputParameters(track: audioTrack)
                    input.audioTapProcessor = meter.processingTap
                    let mix = AVMutableAudioMix()
                    mix.inputParameters = [input]
                    item.audioMix = mix
                    levelTap = meter
                }
            } catch {
                NSLog("SomaFM level meter unavailable: %@", error.localizedDescription)
            }
            guard playbackRequestID == requestID else { return }
            attachAndPlay(item, station: station, requestID: requestID)
        }
    }

    private func attachAndPlay(_ item: AVPlayerItem, station: Station, requestID: UUID) {
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.playbackRequestID == requestID,
                      self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.message = item.error?.localizedDescription ?? "Audio playback could not start."
                    self.failPlayback()
                } else if item.status == .readyToPlay {
                    self.player.play()
                    self.isPlaying = true
                    self.updateStreamHealth()
                    self.playbackStartedAt = Date()
                    self.startTrackUpdates(for: station.id)
                    self.startPlayTimeUpdates()
                }
            }
        }
        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                guard let self else { return }
                self.message = error?.localizedDescription ?? "Audio playback stopped unexpectedly."
                self.failPlayback()
            }
        }
        player.replaceCurrentItem(with: item)
    }

    func togglePlayback() {
        guard currentStation != nil else { return }
        if isPlaying {
            recordPlayTime()
            player.pause()
            isPlaying = false
            playTimeTask?.cancel()
            trackTask?.cancel()
        } else if player.currentItem != nil {
            player.play()
            isPlaying = true
            playbackStartedAt = Date()
            startPlayTimeUpdates()
            if let currentStation { startTrackUpdates(for: currentStation.id) }
        } else if let currentStation {
            play(currentStation)
        }
    }

    func stopPlayback() {
        playbackRequestID = UUID()
        recordPlayTime()
        player.pause()
        player.replaceCurrentItem(with: nil)
        playbackStopped = true
        itemObservation = nil
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
            self.playbackFailureObserver = nil
        }
        trackTask?.cancel()
        playTimeTask?.cancel()
        isPlaying = false
        sleepTask?.cancel()
        sleepMinutes = 0
        sleepDeadline = nil
        level = 0
        trackTitle = ""
        trackArtist = ""
        streamHealth = .idle
    }

    func listeningTime(for station: Station) -> String {
        var seconds = playTimes[station.id, default: 0]
        if isPlaying, currentStation?.id == station.id, let playbackStartedAt {
            seconds += Int(Date().timeIntervalSince(playbackStartedAt))
        }
        let minutes = seconds / 60
        return String(format: "%02d:%02d:%02d", minutes / 1440, (minutes % 1440) / 60, minutes % 60)
    }

    private func updateStreamHealth() {
        if streamHealth == .offline, playbackStopped { return }
        guard currentStation != nil, !playbackStopped else {
            streamHealth = .idle
            return
        }
        guard isPlaying else {
            streamHealth = player.currentItem == nil ? .connecting : .paused
            return
        }
        switch player.timeControlStatus {
        case .playing:
            streamHealth = .healthy
        case .waitingToPlayAtSpecifiedRate:
            streamHealth = .buffering
        case .paused:
            streamHealth = .connecting
        @unknown default:
            streamHealth = .buffering
        }
    }

    private func failPlayback() {
        stopPlayback()
        streamHealth = .offline
    }

    private func startTrackUpdates(for stationID: String) {
        trackTask?.cancel()
        trackTask = Task {
            while !Task.isCancelled {
                do {
                    let track = try await SomaFMService.fetchTrack(id: stationID)
                    guard !Task.isCancelled, currentStation?.id == stationID else { return }
                    guard !track.title.isEmpty || !track.artist.isEmpty else {
                        try? await Task.sleep(for: .seconds(20))
                        continue
                    }
                    let trackKey = "\(stationID)|\(track.title)|\(track.artist)"
                    if lastTrackKey != trackKey {
                        lastTrackKey = trackKey
                        let entry = TrackEntry(
                            station: currentStation?.title ?? stationID,
                            title: track.title, artist: track.artist, playedAt: Date()
                        )
                        if recentTracks.first?.display != entry.display {
                            recentTracks = Array(([entry] + recentTracks).prefix(30))
                            saveConfiguration()
                        }
                    }
                    trackTitle = track.title
                    trackArtist = track.artist
                } catch {
                    if !Task.isCancelled {
                        NSLog("SomaFM track metadata request failed: %@", error.localizedDescription)
                    }
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func startPlayTimeUpdates() {
        playTimeTask?.cancel()
        playTimeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                recordPlayTime()
            }
        }
    }

    private func recordPlayTime() {
        guard isPlaying, let currentStation, let playbackStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(playbackStartedAt))
        guard elapsed > 0 else { return }
        playTimes[currentStation.id, default: 0] += elapsed
        self.playbackStartedAt = playbackStartedAt.addingTimeInterval(TimeInterval(elapsed))
        saveConfiguration()
    }

    private func loadConfiguration() {
        defer { isLoadingConfiguration = false }
        do {
            let data = try Data(contentsOf: configURL)
            guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            let config = try JSONDecoder().decode(SavedConfiguration.self, from: data)
            stations = config.stations.filter(SomaFMService.isValid)
            savedFavorites = config.favorites.filter(SomaFMService.isValid)
            favoriteIDs = Set(savedFavorites.map(\.id))
            favoriteSort = config.favoriteSort == "time" ? "time" : "name"
            playTimes = config.playTimes.filter { $0.value >= 0 }
            volume = min(1, max(0, config.volume))
            autoPlay = config.autoPlay ?? false
            showTrack = config.showTrack ?? false
            recentTracks = Array((config.recentTracks ?? []).prefix(30))
            if let last = config.lastStation, SomaFMService.isValid(last) { currentStation = last }
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                message = "Could not read the saved SomaFM station configuration: \(error.localizedDescription)"
            }
        }
    }

    private func saveConfiguration() {
        guard !isLoadingConfiguration else { return }
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let favoriteStations = favoriteIDs.compactMap { id in
                stations.first { $0.id == id } ?? savedFavorites.first { $0.id == id }
            }
            let config = SavedConfiguration(
                stations: stations,
                favorites: favoriteStations,
                favoriteSort: favoriteSort,
                playTimes: playTimes,
                volume: volume,
                autoPlay: autoPlay,
                showTrack: showTrack,
                recentTracks: recentTracks,
                lastStation: currentStation
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: configURL, options: .atomic)
        } catch {
            message = "Could not save the SomaFM station configuration: \(error.localizedDescription)"
        }
    }
}

enum StreamHealth: Equatable {
    case idle
    case connecting
    case healthy
    case buffering
    case paused
    case offline
}

private struct CatalogResult {
    var stations: [Station]
    var skipped: Int
}

private struct Track {
    var title: String
    var artist: String
}

private enum SomaFMService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()
    private static let channelPattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9-]{0,47}$")

    static func isValid(_ station: Station) -> Bool {
        guard matches(channelPattern, station.id),
              station.title.count <= 100,
              station.bitrate > 0,
              let url = URL(string: station.url),
              url.scheme == "https",
              url.host?.range(of: #"^ice[0-9]+\.somafm\.com$"#, options: .regularExpression) != nil,
              url.path.range(of: #"^/[a-z0-9-]+$"#, options: .regularExpression) != nil
        else { return false }
        return true
    }

    static func fetchCatalog() async throws -> CatalogResult {
        let data = try await fetchData(
            "https://api.somafm.com/channels.json",
            host: "api.somafm.com",
            limit: 512 * 1024
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = root["channels"] as? [[String: Any]],
              !channels.isEmpty, channels.count <= 120
        else { throw ServiceError.invalidCatalog }

        var verified: [Station] = []
        for offset in stride(from: 0, to: channels.count, by: 8) {
            let end = min(offset + 8, channels.count)
            await withTaskGroup(of: Station?.self) { group in
                for channel in channels[offset..<end] {
                    group.addTask { await fetchChannel(channel) }
                }
                for await station in group {
                    if let station { verified.append(station) }
                }
            }
        }
        verified.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return CatalogResult(stations: verified, skipped: max(0, channels.count - verified.count))
    }

    static func fetchTrack(id: String) async throws -> Track {
        guard matches(channelPattern, id) else { throw ServiceError.invalidCatalog }
        let data = try await fetchData("https://somafm.com/songs/\(id).json", host: "somafm.com", limit: 64 * 1024)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let songs = root?["songs"] as? [[String: Any]]
        let first = songs?.first ?? [:]
        return Track(
            title: clean(first["title"] as? String, limit: 160),
            artist: clean(first["artist"] as? String, limit: 120)
        )
    }

    private static func fetchChannel(_ channel: [String: Any]) async -> Station? {
        guard let id = channel["id"] as? String, matches(channelPattern, id),
              let playlists = channel["playlists"] as? [[String: Any]], playlists.count <= 20
        else { return nil }
        let candidates = playlists.compactMap { playlist -> (String, URL)? in
            guard let rawURL = playlist["url"] as? String,
                  let url = URL(string: rawURL), url.scheme == "https",
                  url.host == "api.somafm.com", url.port == nil,
                  url.path.range(
                    of: "^/\(NSRegularExpression.escapedPattern(for: id))[0-9]*\\.pls$",
                    options: .regularExpression
                  ) != nil
            else { return nil }
            return ((playlist["quality"] as? String ?? "").lowercased(), url)
        }
        let preferred = candidates.filter { $0.0 == "highest" }
        let selected = preferred.isEmpty ? candidates : preferred
        var streamCandidates: [(Int, URL)] = []
        for (_, playlistURL) in selected {
            guard let data = try? await fetchData(
                playlistURL.absoluteString,
                host: "api.somafm.com",
                limit: 32 * 1024
            ), let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) where line.lowercased().hasPrefix("file") {
                guard let value = line.split(separator: "=", maxSplits: 1).last,
                      let url = URL(string: String(value).trimmingCharacters(in: .whitespacesAndNewlines)),
                      validStreamURL(url, channelID: id)
                else { continue }
                streamCandidates.append((bitrate(url), url))
            }
        }
        let unique = Dictionary(grouping: streamCandidates, by: { $0.1.path })
        var verified: [(Int, URL)] = []
        for options in unique.values {
            for (pathBitrate, url) in options.sorted(by: { $0.0 > $1.0 }) {
                if let reported = await probe(url) {
                    verified.append((reported > 0 ? reported : pathBitrate, url))
                    break
                }
            }
        }
        guard let best = verified.max(by: { $0.0 < $1.0 }), best.0 > 0 else { return nil }
        let image = validImage(channel["image"] as? String ?? "")
        return Station(
            id: id,
            title: clean(channel["title"] as? String, limit: 100).isEmpty
                ? id : clean(channel["title"] as? String, limit: 100),
            description: clean(channel["description"] as? String, limit: 280),
            genre: clean(channel["genre"] as? String, limit: 60),
            image: image,
            bitrate: best.0,
            url: best.1.absoluteString
        )
    }

    private static func fetchData(_ string: String, host: String, limit: Int) async throws -> Data {
        guard let url = URL(string: string) else { throw ServiceError.invalidCatalog }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("SomaFMMenuBar/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode >= 200, http.statusCode < 300,
              http.url?.scheme == "https", http.url?.host == host
        else { throw ServiceError.invalidResponse }
        var data = Data()
        data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= limit else { throw ServiceError.invalidResponse }
        }
        return data
    }

    private static func probe(_ url: URL) async -> Int? {
        await withCheckedContinuation { continuation in
            let delegate = StreamProbeDelegate(url: url, continuation: continuation)
            delegate.start()
        }
    }

    private static func validStreamURL(_ url: URL, channelID: String) -> Bool {
        guard url.scheme == "https", url.host?.range(
            of: #"^ice[0-9]+\.somafm\.com$"#,
            options: .regularExpression
        ) != nil, url.port == nil else { return false }
        return url.path.range(
            of: "^/\(NSRegularExpression.escapedPattern(for: channelID))(?:-[a-z0-9]+)+$",
            options: .regularExpression
        ) != nil
    }

    private static func validImage(_ value: String) -> String {
        guard value.count <= 300,
              let url = URL(string: value),
              url.scheme == "https", url.host == "api.somafm.com",
              url.path.range(
                of: #"^/logos/120/[A-Za-z0-9-]+120\.(png|jpe?g|gif)$"#,
                options: .regularExpression
              ) != nil,
              url.query == nil || url.query?.range(of: #"^v=[0-9]{1,20}$"#, options: .regularExpression) != nil
        else { return "" }
        return value
    }

    private static func bitrate(_ url: URL) -> Int {
        let path = url.path.lowercased()
        let patterns = [#"(?:-|/)([0-9]{2,3})-(?:mp3|aacp?|ogg|opus)$"#, #"([0-9]{2,3})\.(?:mp3|aacp?|ogg|opus)$"#]
        for pattern in patterns {
            if let range = path.range(of: pattern, options: .regularExpression),
               let number = path[range].range(of: #"[0-9]{2,3}"#, options: .regularExpression) {
                return Int(path[number]) ?? 0
            }
        }
        return 0
    }

    private static func clean(_ value: String?, limit: Int) -> String {
        String((value ?? "").filter { $0 >= " " && $0 != "\u{7f}" }.prefix(limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}

private final class StreamProbeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let continuation: CheckedContinuation<Int?, Never>
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var completed = false

    init(url: URL, continuation: CheckedContinuation<Int?, Never>) {
        self.url = url
        self.continuation = continuation
    }

    func start() {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("SomaFMMenuBar/1.0", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        let finalURL = response.url
        let valid = http.map { (200..<300).contains($0.statusCode) } == true
            && finalURL?.scheme == "https"
            && finalURL?.host?.range(of: #"^ice[0-9]+\.somafm\.com$"#, options: .regularExpression) != nil
        let rawBitrate = http?.allHeaderFields.first {
            String(describing: $0.key).lowercased() == "icy-br"
        }?.value
        let reported = Int(String(describing: rawBitrate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        finish(valid ? reported : nil)
        completionHandler(.cancel)
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            finish(nil)
            session.invalidateAndCancel()
            self.session = nil
            self.task = nil
        }
    }

    private func finish(_ result: Int?) {
        guard !completed else { return }
        completed = true
        continuation.resume(returning: result)
    }
}

private enum ServiceError: LocalizedError {
    case invalidCatalog
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The SomaFM catalog response was invalid."
        case .invalidResponse: "SomaFM returned an invalid or oversized response."
        }
    }
}
