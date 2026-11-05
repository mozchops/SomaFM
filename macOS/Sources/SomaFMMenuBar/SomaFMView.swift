import SwiftUI
import AppKit

/// Colours sampled from the Omarchy widget's preview.png.
enum Theme {
    static let background = Color(red: 0x14 / 255, green: 0x24 / 255, blue: 0x1f / 255)
    static let foreground = Color(red: 0xcc / 255, green: 0xcd / 255, blue: 0xa7 / 255)
    static let secondary = Color(red: 0x98 / 255, green: 0x9c / 255, blue: 0x80 / 255)
    static let accent = Color(red: 0x60 / 255, green: 0xa3 / 255, blue: 0x87 / 255)
    static let card = Color(red: 0x24 / 255, green: 0x32 / 255, blue: 0x2a / 255)
    static let row = Color(red: 0x1d / 255, green: 0x2c / 255, blue: 0x25 / 255)
    static let rowCurrent = Color(red: 0x22 / 255, green: 0x3c / 255, blue: 0x33 / 255)
    static let buttonBorder = Color(red: 0x69 / 255, green: 0x71 / 255, blue: 0x5c / 255)
    static let urgent = Color(red: 0xe0 / 255, green: 0x6c / 255, blue: 0x75 / 255)

    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }
}

struct SomaFMView: View {
    @Bindable var model: SomaFMModel
    var closePopover: () -> Void = {}

    @State private var settingsOpen = false
    @State private var showHistory = false
    @State private var copyFeedback = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            controls
            if showHistory { historyList } else { stationList }
        }
        .padding(14)
        .frame(width: 380, height: 760, alignment: .top)
        .background(Theme.background)
        .overlay(Rectangle().stroke(Theme.accent, lineWidth: 2))
        .foregroundStyle(Theme.foreground)
        .environment(\.colorScheme, .dark)
        .onAppear { searchFocused = true }
        .onExitCommand { closePopover() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("SomaFM stations").font(Theme.font(14, bold: true)).lineLimit(1)
                Spacer(minLength: 0)
                button(settingsOpen ? "Advanced settings \u{25B4}" : "Advanced settings \u{25BE}", width: 150) {
                    settingsOpen.toggle()
                }
            }

            nowPlayingCard

            HStack(spacing: 8) {
                button(model.isPlaying ? "Pause" : "Play", enabled: model.currentStation != nil) {
                    model.togglePlayback()
                }
                button("Stop", enabled: model.currentStation != nil) { model.stopPlayback() }
                button("Copy song", enabled: !model.trackTitle.isEmpty) { copySong(model.trackLabel) }
            }

            volumeControl

            if settingsOpen { settings }

            if model.isLoading {
                note("Checking current streams\u{2026}", color: Theme.secondary)
            }
            if !model.warning.isEmpty { note(model.warning, color: Theme.secondary) }
            if !model.message.isEmpty { note(model.message, color: Theme.urgent) }
            if !copyFeedback.isEmpty { note(copyFeedback, color: Theme.secondary) }

            HStack(spacing: 8) {
                button("Stations", enabled: showHistory) { showHistory = false }
                button("History (\(model.recentTracks.count))", enabled: !showHistory) { showHistory = true }
            }
            .padding(.top, 2)

            if !showHistory {
                ZStack(alignment: .leading) {
                    if model.searchText.isEmpty {
                        Text("Search stations, descriptions or genres\u{2026}")
                            .font(Theme.font(10.5))
                            .foregroundStyle(Theme.secondary.opacity(0.8))
                            .padding(.horizontal, 10)
                    }
                    TextField("", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(Theme.font(11))
                        .padding(.horizontal, 10)
                        .focused($searchFocused)
                }
                .frame(height: 32)
                .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.currentStation?.title ?? "SomaFM")
                .font(Theme.font(11, bold: true)).lineLimit(1)
            Text(model.statusLabel)
                .font(Theme.font(10))
                .foregroundStyle(model.streamHealth == .offline ? Theme.urgent : Theme.secondary)
                .lineLimit(1)
            Text(model.trackLabel.isEmpty ? "Waiting for track information\u{2026}" : model.trackLabel)
                .font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 4))
    }

    private var volumeControl: some View {
        VStack(spacing: 4) {
            HStack {
                Text("SomaFM volume")
                Spacer()
                Text("\(Int((model.volume * 100).rounded()))%")
            }
            .font(Theme.font(11))
            GeometryReader { geo in
                let knob: CGFloat = 14
                let x = max(0, min(geo.size.width - knob, geo.size.width * model.volume - knob / 2))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.foreground.opacity(0.18)).frame(height: 6)
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * model.volume, height: 6)
                    Circle().fill(Theme.foreground).frame(width: knob, height: knob).offset(x: x)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    model.volume = max(0, min(1, value.location.x / geo.size.width))
                })
            }
            .frame(height: 20)
        }
    }

    private var settings: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                button("Validate streams", enabled: !model.isLoading) { model.validateStreams() }
                button("Sort: \(model.favoriteSort == "time" ? "Most played" : "A\u{2013}Z")") {
                    model.toggleFavoriteSort()
                }
            }
            button("Reset listening times") { model.resetListeningTimes() }
            HStack(spacing: 8) {
                button("Startup playback: \(model.autoPlay ? "on" : "off")") { model.autoPlay.toggle() }
                button(sleepLabel) { model.cycleSleepTimer() }
            }
            HStack(spacing: 8) {
                Text("Show track name").font(Theme.font(10.5))
                Spacer()
                toggle(model.showTrack) { model.showTrack.toggle() }
            }
            .padding(.top, 2)
        }
    }

    private var sleepLabel: String {
        guard let deadline = model.sleepDeadline else { return "Sleep timer: off" }
        return "Sleep: \(max(0, Int(ceil(deadline.timeIntervalSinceNow / 60)))) min"
    }

    // MARK: Lists

    private var stationList: some View {
        let favorites = model.filteredStations.filter { model.favoriteIDs.contains($0.id) }
        let others = model.filteredStations.filter { !model.favoriteIDs.contains($0.id) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                if !favorites.isEmpty {
                    sectionHeader("Favourites")
                    ForEach(favorites) { stationRow($0) }
                }
                if !others.isEmpty {
                    sectionHeader("All stations")
                    ForEach(others) { stationRow($0) }
                }
                if model.filteredStations.isEmpty && !model.isLoading {
                    Text(model.stations.isEmpty ? "No verified streams are available right now." : "No matching stations.")
                        .font(Theme.font(10.5)).foregroundStyle(Theme.secondary).padding(.vertical, 8)
                }
            }
        }
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                if model.recentTracks.isEmpty {
                    Text("Songs you listen to will appear here.")
                        .font(Theme.font(10.5)).foregroundStyle(Theme.secondary).padding(.vertical, 8)
                }
                ForEach(model.recentTracks) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.display).font(Theme.font(11)).lineLimit(1)
                        Text("\(entry.station) \u{00B7} \(entry.playedAt.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.font(10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        Text("Click to copy artist and title")
                            .font(Theme.font(9.5)).foregroundStyle(Theme.secondary.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(Theme.row, in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    .onTapGesture { copySong(entry.display) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.font(10, bold: true))
            .foregroundStyle(Theme.foreground.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.leading, 4)
    }

    private func stationRow(_ station: Station) -> some View {
        let current = model.currentStation?.id == station.id
        let isFav = model.favoriteIDs.contains(station.id)
        return HStack(spacing: 10) {
            AsyncImage(url: URL(string: station.image)) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text((isFav ? "\u{2605}  " : "") + station.title)
                    .font(Theme.font(11, bold: current)).lineLimit(1)
                Text(station.description.isEmpty ? station.genre : station.description)
                    .font(Theme.font(9.5)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(station.bitrate) kbps")
                Text(model.listeningTime(for: station))
            }
            .font(Theme.font(9.5)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(current ? Theme.rowCurrent : Theme.row, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { model.play(station) }
        .contextMenu {
            Button(isFav ? "Remove Favourite" : "Add Favourite") { model.toggleFavorite(station) }
        }
    }

    // MARK: Pieces

    private func button(_ title: String, width: CGFloat? = nil, enabled: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(11))
                .lineLimit(1)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width)
                .padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.buttonBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func toggle(_ on: Bool, action: @escaping () -> Void) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Theme.accent : Theme.foreground.opacity(0.15)).frame(width: 42, height: 24)
            Circle().fill(Theme.background).frame(width: 18, height: 18).padding(3)
        }
        .frame(width: 42, height: 24)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.12), value: on)
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text).font(Theme.font(10)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    private func copySong(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyFeedback = "Song copied to clipboard."
        Task {
            try? await Task.sleep(for: .seconds(2))
            copyFeedback = ""
        }
    }
}
