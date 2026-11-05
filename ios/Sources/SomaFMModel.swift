import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UserNotifications

struct TrackHistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var stationTitle: String
    var trackTitle: String
    var trackArtist: String
    var playedAt: Date
}

@Observable @MainActor
final class SomaFMModel {
    private(set) var stations: [Station] = []
    private(set) var currentStation: Station?
    private(set) var isPlaying = false
    private(set) var isPreparingPlayback = false
    private(set) var isLoading = false
    private(set) var trackTitle = ""
    private(set) var trackArtist = ""
    private(set) var message = ""
    private(set) var warning = ""
    private(set) var listeningHistory: [TrackHistoryEntry] = []
    private(set) var playTimes: [String: Int] = [:]
    var searchText = ""
    var selectedStationID: String?
    var volume = 0.8 {
        didSet {
            player.volume = Float(volume)
            saveConfiguration()
        }
    }
    var visualizerMode = "Spectrum" {
        didSet { saveConfiguration() }
    }
    var paletteName = "Spectrum" {
        didSet { saveConfiguration() }
    }
    var notificationsEnabled = false {
        didSet { saveConfiguration() }
    }
    var favoriteSort = "name" {
        didSet { saveConfiguration() }
    }
    var appearance = "System" {
        didSet { saveConfiguration() }
    }
    private(set) var favoriteIDs: Set<String> = []

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var playerObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var spectrumTap: AudioSpectrumTap?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var trackTask: Task<Void, Never>?
    @ObservationIgnored private var playTimeTask: Task<Void, Never>?
    @ObservationIgnored private var playbackStartedAt: Date?
    @ObservationIgnored private var lastTrackKey: String?
    @ObservationIgnored private var playbackRequestID = UUID()
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var savedFavorites: [Station] = []
    @ObservationIgnored private var isLoadingConfiguration = true
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private let configurationURL: URL
    private(set) var peakLevels = Array(repeating: 0.0, count: 12)
    private(set) var waveformSamples = Array(repeating: 0.0, count: 64)

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SomaFM", isDirectory: true)
        configurationURL = support.appendingPathComponent("stations.json")
        loadConfiguration()
        player.volume = Float(volume)
        player.actionAtItemEnd = .pause
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, change in
            guard let status = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard player.timeControlStatus == status, player.currentItem != nil else { return }
                self?.handlePlaybackStatus(status, hasCurrentItem: player.currentItem != nil)
            }
        }
    }

    var filteredStations: [Station] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = stations.filter {
            query.isEmpty
                || $0.title.localizedCaseInsensitiveContains(query)
                || $0.genre.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
        }
        let favorites = matching.filter { favoriteIDs.contains($0.id) }
        let otherStations = matching.filter { !favoriteIDs.contains($0.id) }
        let alphabetical: (Station, Station) -> Bool = {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let sortedFavorites = favoriteSort == "time"
            ? favorites.sorted {
                let left = playTimes[$0.id, default: 0]
                let right = playTimes[$1.id, default: 0]
                return left == right ? alphabetical($0, $1) : left > right
            }
            : favorites.sorted(by: alphabetical)
        return sortedFavorites + otherStations.sorted(by: alphabetical)
    }

    var currentListeningTime: String {
        guard let currentStation else { return "00:00" }
        return listeningTime(for: currentStation)
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        configureAudioSession()
        configureRemoteCommands()
        observeAudioInterruptions()
        refreshStations()
    }

    func refreshStations() {
        guard !isLoading else { return }
        isLoading = true
        message = ""
        warning = ""
        Task {
            do {
                let updated = try await SomaFMService.fetchCatalog()
                guard !updated.isEmpty else {
                    message = "No SomaFM streams could be found right now. Try again in a moment."
                    isLoading = false
                    return
                }
                stations = updated
                for station in updated where favoriteIDs.contains(station.id) {
                    savedFavorites.removeAll { $0.id == station.id }
                    savedFavorites.append(station)
                }
                if let id = selectedStationID, let station = updated.first(where: { $0.id == id }) {
                    selectedStationID = station.id
                    if currentStation?.id == id { currentStation = station }
                }
                saveConfiguration()
            } catch {
                message = "Could not load SomaFM stations: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func select(_ station: Station) {
        selectedStationID = station.id
        play(station)
    }

    func play(_ station: Station) {
        guard let url = URL(string: station.url), url.scheme == "https" else {
            message = "This station has an invalid stream address."
            return
        }
        recordPlayTime()
        playbackStartedAt = nil
        let requestID = UUID()
        playbackRequestID = requestID
        trackTask?.cancel()
        playTimeTask?.cancel()
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        spectrumTap = nil
        currentStation = station
        selectedStationID = station.id
        isPlaying = false
        isPreparingPlayback = true
        trackTitle = ""
        trackArtist = ""
        lastTrackKey = nil
        peakLevels = Array(repeating: 0, count: 12)
        waveformSamples = Array(repeating: 0, count: 64)
        message = ""
        updateNowPlayingInfo()

        let item = AVPlayerItem(url: url)
        Task {
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard playbackRequestID == requestID else { return }
                if let audioTrack = tracks.first {
                    let analyzer = try AudioSpectrumTap.create { [weak self = self] levels, waveform in
                        Task { @MainActor [weak self = self] in
                            guard let self, self.playbackRequestID == requestID else { return }
                            self.peakLevels = levels
                            self.waveformSamples = waveform
                        }
                    }
                    let input = AVMutableAudioMixInputParameters(track: audioTrack)
                    input.audioTapProcessor = analyzer.processingTap
                    let mix = AVMutableAudioMix()
                    mix.inputParameters = [input]
                    item.audioMix = mix
                    spectrumTap = analyzer
                }
            } catch {
                guard playbackRequestID == requestID else { return }
                warning = "The visualizer could not attach to this stream."
            }
            guard playbackRequestID == requestID else { return }
            attachAndPlay(item, requestID: requestID)
        }
    }

    func togglePlayback() {
        guard let currentStation else { return }
        guard !isPreparingPlayback else { return }
        if isPlaying {
            recordPlayTime()
            player.pause()
            isPlaying = false
            playbackStartedAt = nil
            trackTask?.cancel()
            playTimeTask?.cancel()
            updateNowPlayingInfo()
        } else if player.currentItem != nil {
            guard activateAudioSession() else { return }
            isPreparingPlayback = true
            player.play()
            updateNowPlayingInfo()
        } else {
            play(currentStation)
        }
    }

    func stopPlayback() {
        recordPlayTime()
        trackTask?.cancel()
        playTimeTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        spectrumTap = nil
        playbackRequestID = UUID()
        isPlaying = false
        isPreparingPlayback = false
        trackTitle = ""
        trackArtist = ""
        playbackStartedAt = nil
        updateNowPlayingInfo()
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

    func listeningTime(for station: Station) -> String {
        var seconds = playTimes[station.id, default: 0]
        if isPlaying, currentStation?.id == station.id, let playbackStartedAt {
            seconds += Int(Date().timeIntervalSince(playbackStartedAt))
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

    func clearListeningHistory() {
        listeningHistory.removeAll()
        saveConfiguration()
    }

    func cyclePalette() {
        let palettes = ["Spectrum", "Aurora", "Monochrome"]
        let index = palettes.firstIndex(of: paletteName) ?? 0
        paletteName = palettes[(index + 1) % palettes.count]
    }

    func dismissMessage() {
        message = ""
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard enabled else {
            notificationsEnabled = false
            warning = ""
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied {
            notificationsEnabled = false
            warning = "Notifications are disabled for SomaFM in iPad Settings."
            return
        }
        do {
            let granted: Bool
            if settings.authorizationStatus == .authorized {
                granted = true
            } else {
                granted = try await center.requestAuthorization(options: [.alert, .sound])
            }
            notificationsEnabled = granted
            warning = granted ? "" : "Notification permission was not granted."
        } catch {
            notificationsEnabled = false
            warning = "Could not enable notifications: \(error.localizedDescription)"
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
        } catch {
            warning = "Could not configure audio: \(error.localizedDescription)"
        }
    }

    private func activateAudioSession() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch {
            warning = "Could not start audio: \(error.localizedDescription)"
            return false
        }
    }

    private func handlePlaybackStatus(
        _ status: AVPlayer.TimeControlStatus,
        hasCurrentItem: Bool
    ) {
        guard hasCurrentItem else { return }
        switch status {
        case .playing:
            isPreparingPlayback = false
            isPlaying = true
            if playbackStartedAt == nil {
                playbackStartedAt = Date()
                if let currentStation {
                    startMetadataUpdates(for: currentStation.id)
                }
                startPlayTimeUpdates()
            }
            updateNowPlayingInfo()
        case .waitingToPlayAtSpecifiedRate:
            if isPlaying { recordPlayTime() }
            playbackStartedAt = nil
            isPlaying = false
            isPreparingPlayback = true
            updateNowPlayingInfo()
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func attachAndPlay(_ item: AVPlayerItem, requestID: UUID) {
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackRequestID == requestID,
                      self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    guard self.activateAudioSession() else {
                        self.isPreparingPlayback = false
                        self.message = self.warning
                        self.updateNowPlayingInfo()
                        return
                    }
                    self.isPreparingPlayback = true
                    self.player.play()
                    self.updateNowPlayingInfo()
                case .failed:
                    self.isPreparingPlayback = false
                    self.isPlaying = false
                    self.message = item.error?.localizedDescription ?? "Playback could not start."
                    self.updateNowPlayingInfo()
                default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began {
                    self.recordPlayTime()
                    self.player.pause()
                    self.isPlaying = false
                    self.isPreparingPlayback = false
                    self.playbackStartedAt = nil
                } else if let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                          AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    self.togglePlayback()
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func configureRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        let play = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        let pause = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        let toggle = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayback() }
            return .success
        }
        remoteTargets = [(center.playCommand, play), (center.pauseCommand, pause),
                         (center.togglePlayPauseCommand, toggle)]
    }

    private func updateNowPlayingInfo() {
        guard let currentStation else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: trackTitle.isEmpty ? currentStation.title : trackTitle,
            MPMediaItemPropertyArtist: trackArtist.isEmpty ? "SomaFM" : trackArtist,
            MPMediaItemPropertyAlbumTitle: currentStation.title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func startMetadataUpdates(for stationID: String) {
        trackTask?.cancel()
        trackTask = Task {
            while !Task.isCancelled {
                do {
                    let track = try await SomaFMService.fetchTrack(id: stationID)
                    guard !Task.isCancelled, currentStation?.id == stationID else { return }
                    trackTitle = track.title
                    trackArtist = track.artist
                    if !track.title.isEmpty || !track.artist.isEmpty {
                        let key = "\(stationID)|\(track.title)|\(track.artist)"
                        if key != lastTrackKey {
                            lastTrackKey = key
                            if let station = currentStation {
                                recordTrack(station: station, track: track)
                            }
                        }
                    }
                    updateNowPlayingInfo()
                } catch {
                    if !Task.isCancelled {
                        warning = "Track information is temporarily unavailable."
                    }
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func recordTrack(station: Station, track: Track) {
        let entry = TrackHistoryEntry(
            stationTitle: station.title,
            trackTitle: track.title,
            trackArtist: track.artist,
            playedAt: Date()
        )
        listeningHistory.insert(entry, at: 0)
        listeningHistory = Array(listeningHistory.prefix(100))
        saveConfiguration()
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = station.title
        content.subtitle = "Now playing"
        content.body = track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        ) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.warning = "Could not show a notification: \(error.localizedDescription)"
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
            let data = try Data(contentsOf: configurationURL)
            guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            let config = try JSONDecoder().decode(SavedConfiguration.self, from: data)
            stations = config.stations
            savedFavorites = config.favorites
            favoriteIDs = Set(config.favorites.map(\.id))
            favoriteSort = config.favoriteSort == "time" ? "time" : "name"
            appearance = ["System", "Light", "Dark"].contains(config.appearance)
                ? config.appearance : "System"
            playTimes = config.playTimes.filter { $0.value >= 0 }
            volume = min(1, max(0, config.volume))
            visualizerMode = config.visualizerMode == "Waveform" ? "Waveform" : "Spectrum"
            paletteName = ["Spectrum", "Aurora", "Monochrome"].contains(config.paletteName)
                ? config.paletteName : "Spectrum"
            notificationsEnabled = config.notificationsEnabled
            listeningHistory = Array(config.listeningHistory.prefix(100))
            selectedStationID = config.selectedStationID
            currentStation = stations.first { $0.id == selectedStationID }
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                message = "Could not read saved iPad settings: \(error.localizedDescription)"
            }
        }
    }

    private func saveConfiguration() {
        guard !isLoadingConfiguration else { return }
        do {
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(),
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
                visualizerMode: visualizerMode,
                paletteName: paletteName,
                notificationsEnabled: notificationsEnabled,
                listeningHistory: listeningHistory,
                selectedStationID: selectedStationID,
                appearance: appearance
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: configurationURL, options: .atomic)
        } catch {
            message = "Could not save iPad settings: \(error.localizedDescription)"
        }
    }
}

private struct SavedConfiguration: Codable {
    var stations: [Station]
    var favorites: [Station]
    var favoriteSort: String
    var playTimes: [String: Int]
    var volume: Double
    var visualizerMode: String
    var paletteName: String
    var notificationsEnabled: Bool
    var listeningHistory: [TrackHistoryEntry]
    var selectedStationID: String?
    var appearance: String

    private enum CodingKeys: String, CodingKey {
        case stations, favorites, favoriteSort, playTimes, volume
        case visualizerMode, paletteName, notificationsEnabled, listeningHistory, selectedStationID
        case appearance
    }

    init(
        stations: [Station],
        favorites: [Station],
        favoriteSort: String,
        playTimes: [String: Int],
        volume: Double,
        visualizerMode: String,
        paletteName: String,
        notificationsEnabled: Bool,
        listeningHistory: [TrackHistoryEntry],
        selectedStationID: String?,
        appearance: String
    ) {
        self.stations = stations
        self.favorites = favorites
        self.favoriteSort = favoriteSort
        self.playTimes = playTimes
        self.volume = volume
        self.visualizerMode = visualizerMode
        self.paletteName = paletteName
        self.notificationsEnabled = notificationsEnabled
        self.listeningHistory = listeningHistory
        self.selectedStationID = selectedStationID
        self.appearance = appearance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stations = try values.decodeIfPresent([Station].self, forKey: .stations) ?? []
        favorites = try values.decodeIfPresent([Station].self, forKey: .favorites) ?? []
        favoriteSort = try values.decodeIfPresent(String.self, forKey: .favoriteSort) ?? "name"
        playTimes = try values.decodeIfPresent([String: Int].self, forKey: .playTimes) ?? [:]
        volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8
        visualizerMode = try values.decodeIfPresent(String.self, forKey: .visualizerMode) ?? "Spectrum"
        paletteName = try values.decodeIfPresent(String.self, forKey: .paletteName) ?? "Spectrum"
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        listeningHistory = try values.decodeIfPresent([TrackHistoryEntry].self, forKey: .listeningHistory) ?? []
        selectedStationID = try values.decodeIfPresent(String.self, forKey: .selectedStationID)
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "System"
    }
}
