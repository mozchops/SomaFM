import AppKit
import MediaPlayer
import SwiftUI

@main
@MainActor
struct SomaFMMenuBarApp: App {
    @NSApplicationDelegateAdaptor(SomaFMAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class SomaFMAppDelegate: NSObject, NSApplicationDelegate {
    private let model = SomaFMModel()
    private var statusItem: NSStatusItem?
    private let panel = PopupPanel()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        panel.contentView = NSHostingView(rootView: SomaFMView(
            model: model, closePopover: { [weak self] in self?.panel.orderOut(nil) }
        ))
        panel.setContentSize(NSSize(width: 380, height: 760))

        model.onStatusChanged = { [weak self] in
            self?.updateStatusItem()
        }
        model.onNowPlayingChanged = { [weak self] in
            self?.updateNowPlayingInfo()
            self?.updateStatusItemToolTip()
            self?.updateStatusItem()
        }
        model.onLevelChanged = { [weak self] in self?.updateStatusItem() }
        configureRemoteCommands()
        model.startIfAutoPlay()
        updateStatusItem()
        updateStatusItemToolTip()
        updateNowPlayingInfo()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    @objc private func togglePopover(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            model.togglePlayback()
            return
        }

        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        if model.stations.isEmpty { model.validateStreams() }
        let anchor = buttonWindow.frame
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - 4))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        var title = model.currentStation?.title ?? "SomaFM"
        if title.count > 30 { title = String(title.prefix(29)) + "\u{2026}" }
        if model.showTrack, !model.trackLabel.isEmpty {
            var track = model.trackLabel
            if track.count > 32 { track = String(track.prefix(31)) + "\u{2026}" }
            title += " - " + track
        }
        button.title = ""
        button.image = makeWidgetImage(title: title, level: model.isPlaying ? model.level : 0)
        button.needsDisplay = true
    }

    /// Mirrors the Omarchy bar widget: a thin rounded outline around a small
    /// level meter and the station name. Drawn lazily so it follows the menu bar's appearance.
    private func makeWidgetImage(title: String, level: Double) -> NSImage {
        let thickness = NSStatusBar.system.thickness
        let font = NSFont.systemFont(ofSize: 12)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let padding: CGFloat = 5, meterWidth: CGFloat = 4, gap: CGFloat = 6
        let size = NSSize(width: padding + meterWidth + gap + textWidth + padding + 2, height: thickness)
        let image = NSImage(size: size, flipped: false) { _ in
            // Same palette as the popup (Theme in SomaFMView.swift).
            let foreground = NSColor(srgbRed: 0xcc / 255, green: 0xcd / 255, blue: 0xa7 / 255, alpha: 1)
            let background = NSColor(srgbRed: 0x14 / 255, green: 0x24 / 255, blue: 0x1f / 255, alpha: 1)
            let accent = NSColor(srgbRed: 0x60 / 255, green: 0xa3 / 255, blue: 0x87 / 255, alpha: 1)
            let boxHeight = thickness * 0.7
            let box = NSRect(x: 0.5, y: (thickness - boxHeight) / 2, width: size.width - 1, height: boxHeight)
            let outline = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            outline.lineWidth = 1
            background.setFill()
            outline.fill()
            accent.setStroke()
            outline.stroke()

            let meterHeight = max(2, thickness * 0.45 * CGFloat(level))
            accent.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: padding + 1, y: thickness * 0.3, width: meterWidth, height: meterHeight),
                xRadius: 2, yRadius: 2
            ).fill()

            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
            let textHeight = (title as NSString).size(withAttributes: attributes).height
            (title as NSString).draw(
                at: NSPoint(x: padding + 1 + meterWidth + gap, y: (thickness - textHeight) / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private func updateStatusItemToolTip() {
        guard let button = statusItem?.button else { return }
        guard let station = model.currentStation else {
            button.toolTip = "SomaFM \u{2014} Choose a station"
            return
        }

        let track = model.trackTitle.isEmpty
            ? "Live radio"
            : model.trackArtist.isEmpty
                ? model.trackTitle
                : "\(model.trackTitle) \u{2014} \(model.trackArtist)"
        let state = model.isPlaying ? "Playing" : (model.playbackStopped ? "Stopped" : "Paused")
        let codec = station.url.split(separator: "/").last
            .flatMap { $0.split(separator: "-").last }
            .map { $0.uppercased() } ?? ""
        let quality = ["\(station.bitrate) kbps", codec].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        button.toolTip = "\(station.title)\n\(track)\n\(quality)\n\(state)"
    }

    private func configureRemoteCommands() {
        addRemoteTarget(remoteCommandCenter.playCommand) { [weak self] in
            guard let self, self.model.currentStation != nil else { return .noSuchContent }
            if !self.model.isPlaying { self.model.togglePlayback() }
            return .success
        }
        addRemoteTarget(remoteCommandCenter.pauseCommand) { [weak self] in
            guard let self, self.model.currentStation != nil else { return .noSuchContent }
            if self.model.isPlaying { self.model.togglePlayback() }
            return .success
        }
        addRemoteTarget(remoteCommandCenter.togglePlayPauseCommand) { [weak self] in
            guard let self, self.model.currentStation != nil else { return .noSuchContent }
            self.model.togglePlayback()
            return .success
        }
        addRemoteTarget(remoteCommandCenter.stopCommand) { [weak self] in
            guard let self, self.model.currentStation != nil else { return .noSuchContent }
            self.model.stopPlayback()
            return .success
        }
        remoteCommandCenter.nextTrackCommand.isEnabled = false
        remoteCommandCenter.previousTrackCommand.isEnabled = false
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    private func addRemoteTarget(
        _ command: MPRemoteCommand,
        handler: @escaping @MainActor () -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget { _ in
            Task { @MainActor in
                _ = handler()
            }
            return .success
        }
        remoteCommandTargets.append((command, target))
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let station = model.currentStation else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            setRemoteCommandsEnabled(false)
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: model.trackTitle.isEmpty ? station.title : model.trackTitle,
            MPMediaItemPropertyAlbumTitle: "SomaFM",
            MPMediaItemPropertyGenre: station.genre,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: model.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        let artist = model.trackArtist.isEmpty ? "SomaFM" : model.trackArtist
        info[MPMediaItemPropertyArtist] = artist
        center.nowPlayingInfo = info
        center.playbackState = model.isPlaying ? .playing : (model.playbackStopped ? .stopped : .paused)
        setRemoteCommandsEnabled(true)
    }

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        remoteCommandCenter.playCommand.isEnabled = enabled
        remoteCommandCenter.pauseCommand.isEnabled = enabled
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = enabled
        remoteCommandCenter.stopCommand.isEnabled = enabled
    }
}


/// Borderless dark panel shown under the menu bar item. It closes when it loses focus.
final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 760),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
