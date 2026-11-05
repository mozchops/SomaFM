import SwiftUI
import AVKit
import UIKit

struct SomaFMView: View {
    @Bindable var model: SomaFMModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSettings = false

    private var favoriteStations: [Station] {
        model.filteredStations.filter { model.favoriteIDs.contains($0.id) }
    }

    private var otherStations: [Station] {
        model.filteredStations.filter { !model.favoriteIDs.contains($0.id) }
    }

    private var appearanceColorScheme: ColorScheme? {
        switch model.appearance {
        case "Light": .light
        case "Dark": .dark
        default: nil
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    stationList(compactNavigation: true)
                }
            } else {
                NavigationSplitView {
                    stationList(compactNavigation: false)
                } detail: {
                    detailContent
                }
            }
        }
        .task { model.start() }
        .onChange(of: model.selectedStationID) { _, newValue in
            guard let newValue,
                  let station = model.stations.first(where: { $0.id == newValue }),
                  model.currentStation?.id != station.id else { return }
            model.select(station)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
        .alert("SomaFM", isPresented: messagePresented) {
            Button("OK") { model.dismissMessage() }
        } message: {
            Text(model.message)
        }
        .preferredColorScheme(appearanceColorScheme)
    }

    private func stationList(compactNavigation: Bool) -> some View {
        List(selection: $model.selectedStationID) {
            if model.isLoading && model.stations.isEmpty {
                HStack {
                    Spacer()
                    loadingStationsContent
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
            if !favoriteStations.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteStations) { station in
                        stationRow(station, compactNavigation: compactNavigation)
                    }
                }
            }
            Section("Stations") {
                ForEach(otherStations) { station in
                    stationRow(station, compactNavigation: compactNavigation)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SomaFM")
        .searchable(text: $model.searchText, prompt: "Search stations")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.toggleFavoriteSort()
                } label: {
                    Label(
                        model.favoriteSort == "time" ? "Favorites by play time" : "Favorites A to Z",
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .accessibilityLabel("Sort favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.refreshStations()
                } label: {
                    if model.isLoading && model.stations.isEmpty {
                        ProgressView()
                    } else {
                        Label("Refresh stations", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isLoading)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings and history", systemImage: "gearshape")
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                loadingStationsContent
            }
            Group {
                if let station = model.currentStation {
                    NowPlayingView(model: model, station: station)
                        .id(station.id)
                } else {
                    ContentUnavailableView {
                        Label("Choose a station", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("Select a SomaFM station to start listening.")
                    } actions: {
                        Button("Refresh stations") { model.refreshStations() }
                            .disabled(model.isLoading)
                    }
                }
            }
        }
    }

    private var loadingStationsContent: some View {
        VStack(spacing: 10) {
            ProgressView("Loading stations…")
            Text("Loading the station list can take a little while, especially on first launch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var messagePresented: Binding<Bool> {
        Binding(
            get: { !model.message.isEmpty },
            set: { if !$0 { model.dismissMessage() } }
        )
    }

    @ViewBuilder
    private func stationRow(_ station: Station, compactNavigation: Bool) -> some View {
        if compactNavigation {
            NavigationLink {
                NowPlayingView(model: model, station: station)
                    .id(station.id)
                    .onAppear {
                        if model.currentStation?.id != station.id {
                            model.select(station)
                        }
                    }
            } label: {
                stationRowContent(station)
            }
            .tag(station.id)
        } else {
            stationRowContent(station)
                .tag(station.id)
        }
    }

    private func stationRowContent(_ station: Station) -> some View {
        HStack(spacing: 12) {
            StationArtwork(station: station, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(station.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(station.genre.isEmpty ? station.description : station.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.currentStation?.id == station.id && model.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Playing")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct NowPlayingView: View {
    @Bindable var model: SomaFMModel
    let station: Station
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if horizontalSizeClass == .compact && geometry.size.width > geometry.size.height {
                        phoneLandscapeLayout(for: geometry.size)
                    } else if horizontalSizeClass == .compact {
                        phonePortraitLayout(for: geometry.size)
                    } else if geometry.size.width > geometry.size.height {
                        landscapeLayout(for: geometry.size)
                    } else {
                        portraitLayout(for: geometry.size)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func phonePortraitLayout(for size: CGSize) -> some View {
        let artworkSize = max(1, min(180, size.width - 40))

        return VStack(spacing: 12) {
            favoriteButton
            StationArtwork(station: station, size: artworkSize)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            compactStationInformation(alignment: .center)
            visualizer(height: 52)
            compactVisualizerControls
            compactPlaybackControls
            volumeControl
            stationDescription(alignment: .center)
            warningMessage
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func phoneLandscapeLayout(for size: CGSize) -> some View {
        let artworkSize = max(1, min(128, size.height * 0.38))

        return HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 8) {
                StationArtwork(station: station, size: artworkSize)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
                visualizer(height: 48)
                compactVisualizerControls
            }
            .frame(maxWidth: size.width * 0.40)

            VStack(spacing: 12) {
                favoriteButton
                compactStationInformation(alignment: .leading)
                compactPlaybackControls
                volumeControl
                stationDescription(alignment: .leading)
                warningMessage
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func portraitLayout(for size: CGSize) -> some View {
        let artworkSize = max(1, min(270, size.width - 64))

        return VStack(spacing: 24) {
            favoriteButton
            StationArtwork(station: station, size: artworkSize)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            stationInformation(alignment: .center)
            visualizer()
            visualizerControls
            playbackControls
            volumeControl
            stationDescription(alignment: .center)
            warningMessage
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    private func landscapeLayout(for size: CGSize) -> some View {
        let artworkSize = min(210, max(140, size.height * 0.30))

        return HStack(alignment: .center, spacing: 28) {
            VStack(spacing: 14) {
                StationArtwork(station: station, size: artworkSize)
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                visualizer(height: 86)
                visualizerControls
            }
            .frame(maxWidth: size.width * 0.42)

            VStack(spacing: 16) {
                favoriteButton
                stationInformation(alignment: .leading)
                playbackControls
                volumeControl
                stationDescription(alignment: .leading)
                warningMessage
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var favoriteButton: some View {
        HStack {
            Spacer()
            Button {
                model.toggleFavorite(station)
            } label: {
                Label(
                    model.favoriteIDs.contains(station.id) ? "Remove favorite" : "Add to favorites",
                    systemImage: model.favoriteIDs.contains(station.id) ? "star.fill" : "star"
                )
            }
            .buttonStyle(.bordered)
        }
    }

    private func stationInformation(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(station.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(alignment == .center ? .center : .leading)
            Text(station.genre.isEmpty ? "SomaFM Radio" : station.genre)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(nowPlayingDescription)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
            if !model.trackArtist.isEmpty {
                Text(model.trackArtist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Label("\(station.bitrate) kbps  ·  Listening \(model.currentListeningTime)",
                  systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func compactStationInformation(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(station.title)
                .font(.title2.bold())
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
            Text(station.genre.isEmpty ? "SomaFM Radio" : station.genre)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(nowPlayingDescription)
                .font(.headline)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
            if !model.trackArtist.isEmpty {
                Text(model.trackArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Label("\(station.bitrate) kbps · \(model.currentListeningTime)",
                  systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func visualizer(height: CGFloat = 120) -> some View {
        VisualizerView(
            levels: model.peakLevels,
            samples: model.waveformSamples,
            mode: model.visualizerMode,
            palette: model.paletteName
        )
        .frame(maxWidth: 520)
        .frame(height: height)
    }

    private var compactVisualizerControls: some View {
        VStack(spacing: 4) {
            Picker("Visualizer style", selection: $model.visualizerMode) {
                Text("Spectrum").tag("Spectrum")
                Text("Waveform").tag("Waveform")
            }
            .pickerStyle(.segmented)
            Button("Palette: \(model.paletteName)") {
                model.cyclePalette()
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
    }

    private var visualizerControls: some View {
        HStack(spacing: 16) {
            Picker("Visualizer style", selection: $model.visualizerMode) {
                Text("Spectrum").tag("Spectrum")
                Text("Waveform").tag("Waveform")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Button("Palette: \(model.paletteName)") {
                model.cyclePalette()
            }
            .buttonStyle(.borderless)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 28) {
            Button {
                model.stopPlayback()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Stop")

            Button {
                model.togglePlayback()
            } label: {
                Group {
                    if model.isPreparingPlayback {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title.bold())
                    }
                }
                .frame(width: 72, height: 72)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingPlayback)
            .accessibilityLabel(model.isPreparingPlayback ? "Connecting" : model.isPlaying ? "Pause" : "Play")

            AirPlayRoutePicker()
                .frame(width: 56, height: 56)
        }
    }

    private var compactPlaybackControls: some View {
        HStack(spacing: 22) {
            Button {
                model.stopPlayback()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Stop")

            Button {
                model.togglePlayback()
            } label: {
                Group {
                    if model.isPreparingPlayback {
                        ProgressView()
                    } else {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2.bold())
                    }
                }
                .frame(width: 60, height: 60)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingPlayback)
            .accessibilityLabel(model.isPreparingPlayback ? "Connecting" : model.isPlaying ? "Pause" : "Play")

            AirPlayRoutePicker()
                .frame(width: 48, height: 48)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(value: $model.volume, in: 0...1)
                .accessibilityLabel("Playback volume")
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 440)
    }

    private func stationDescription(alignment: HorizontalAlignment) -> some View {
        Group {
            if !station.description.isEmpty {
                Text(station.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .frame(maxWidth: 560)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    @ViewBuilder
    private var warningMessage: some View {
        if !model.warning.isEmpty {
            Label(model.warning, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    private var nowPlayingDescription: String {
        if model.isPreparingPlayback { return "Connecting to live radio…" }
        if !model.trackTitle.isEmpty { return model.trackTitle }
        return model.isPlaying ? "Live radio" : "Ready to play"
    }
}

private struct StationArtwork: View {
    let station: Station
    var size: CGFloat

    var body: some View {
        Group {
            if let url = URL(string: station.image), !station.image.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
        .accessibilityLabel("\(station.title) artwork")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.teal.opacity(0.8), .indigo.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.32, weight: .light))
                .foregroundStyle(.white)
        }
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

private struct VisualizerView: View {
    let levels: [Double]
    let samples: [Double]
    let mode: String
    let palette: String

    var body: some View {
        Canvas { context, size in
            if mode == "Waveform" {
                drawWaveform(in: &context, size: size)
            } else {
                drawSpectrum(in: &context, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == "Waveform" ? "Audio waveform" : "Audio spectrum")
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        guard samples.count > 1, size.width > 0, size.height > 0 else { return }
        var path = Path()
        let center = size.height / 2
        let amplitude = size.height * 0.44
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) / CGFloat(samples.count - 1) * size.width
            let y = center - CGFloat(sample) * amplitude
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color(at: 0)), lineWidth: 2.5)
    }

    private func drawSpectrum(in context: inout GraphicsContext, size: CGSize) {
        guard !levels.isEmpty, size.width > 0, size.height > 0 else { return }
        let gap: CGFloat = 6
        let barWidth = (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
        for (index, level) in levels.enumerated() {
            let height = max(4, size.height * CGFloat(min(1, max(0, level))))
            let rect = CGRect(
                x: CGFloat(index) * (barWidth + gap),
                y: size.height - height,
                width: barWidth,
                height: height
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(color(at: index))
            )
        }
    }

    private func color(at index: Int) -> Color {
        switch palette {
        case "Aurora":
            return [.mint, .cyan, .indigo][index % 3]
        case "Monochrome":
            return .primary
        default:
            return Color(hue: 0.48 + 0.035 * Double(index), saturation: 0.78, brightness: 0.92)
        }
    }
}

private struct SettingsView: View {
    @Bindable var model: SomaFMModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Color scheme", selection: $model.appearance) {
                        Text("System").tag("System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Playback") {
                    Toggle(
                        "Track-change notifications",
                        isOn: Binding(
                            get: { model.notificationsEnabled },
                            set: { enabled in
                                Task { await model.setNotificationsEnabled(enabled) }
                            }
                        )
                    )
                    Text("Audio continues while SomaFM is in the background or the iPad is locked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Listening history") {
                    if model.listeningHistory.isEmpty {
                        Text("Played tracks will appear here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.listeningHistory) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.trackTitle.isEmpty ? "Unknown track" : entry.trackTitle)
                                    .font(.body.weight(.medium))
                                Text([entry.trackArtist, entry.stationTitle]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                        Button("Clear listening history", role: .destructive) {
                            model.clearListeningHistory()
                        }
                    }
                }

                if !model.warning.isEmpty {
                    Section {
                        Text(model.warning)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
