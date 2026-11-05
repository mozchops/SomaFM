import AppKit
import SceneKit
import SwiftUI

@main
struct AsteroidsApp: App {
    var body: some Scene {
        WindowGroup {
            AsteroidsGameView()
                .frame(minWidth: 800, minHeight: 600)
                .background(Color(red: 0.012, green: 0.024, blue: 0.045))
        }
        .defaultSize(width: 1180, height: 800)
    }
}

private struct AsteroidsGameView: View {
    @State private var scene = AsteroidsScene()
    @State private var hud = GameHUD()

    var body: some View {
        ZStack {
            SceneKitGameView(scene: scene, hud: $hud)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topInstrumentPanel
                    .padding(.horizontal, 26)
                    .padding(.top, 22)

                Spacer(minLength: 18)

                if hud.isGameOver {
                    statusCard(title: "FLIGHT SYSTEMS OFFLINE", subtitle: "Press R or click to reboot · Final score \(hud.score.formatted())")
                        .padding(.bottom, 20)
                } else if !hud.hasStarted {
                    statusCard(title: "PILOT READY", subtitle: "MOVE MOUSE TO STEER · HOLD W TO THRUST · S TO BRAKE · CLICK TO FIRE")
                        .padding(.bottom, 20)
                }

                Spacer(minLength: 8)

                cockpitConsole
            }

            targetingReticle
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }

    private var topInstrumentPanel: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(hud.isGameOver ? Color.red : Color.cyan)
                        .frame(width: 7, height: 7)
                        .shadow(color: hud.isGameOver ? .red : .cyan, radius: 7)
                    Text("NOVA // FLIGHT DECK")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(Color.cyan.opacity(0.94))
                }
                Text("SECTOR 07  ·  WAVE \(String(format: "%02d", hud.wave))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            instrumentValue(label: "VELOCITY", value: String(format: "%05.1f", hud.speed), suffix: "M/S")
                .frame(width: 112, alignment: .trailing)
            panelDivider
                .padding(.horizontal, 18)
            instrumentValue(label: "SCORE", value: hud.score.formatted(), suffix: "PTS")
                .frame(width: 100, alignment: .trailing)
            panelDivider
                .padding(.horizontal, 18)
            VStack(alignment: .trailing, spacing: 7) {
                Text("HULL INTEGRITY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index < hud.lives ? Color.cyan : Color.white.opacity(0.12))
                            .frame(width: 19, height: 5)
                            .shadow(color: index < hud.lives ? .cyan.opacity(0.75) : .clear, radius: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(instrumentPanel)
    }

    private var cockpitConsole: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    statusLamp(isActive: hud.speed > 0.5, color: .orange)
                    Text("IMPULSE DRIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.65))
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(hud.speed.rounded()))")
                        .font(.system(size: 34, weight: .light, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("M/S")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.8))
                }

                HStack(spacing: 3) {
                    ForEach(0..<18, id: \.self) { index in
                        Capsule()
                            .fill(CGFloat(index) / 18 < min(hud.speed / 36, 1) ? Color.cyan : Color.white.opacity(0.1))
                            .frame(height: index % 3 == 0 ? 8 : 5)
                    }
                }
                .frame(maxWidth: 170)
                .animation(.easeOut(duration: 0.18), value: hud.speed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                Text("THRUST CONTROL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.42))
                HStack(spacing: 10) {
                    thrustButton("BRAKE", symbol: "minus", direction: -1)
                    thrustButton("THRUST", symbol: "arrow.up", direction: 1)
                }
            }

            VStack(alignment: .trailing, spacing: 11) {
                HStack(spacing: 7) {
                    Text("WEAPONS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.65))
                    statusLamp(isActive: true, color: .green)
                }
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                        .foregroundStyle(Color.cyan)
                    Text("TWIN PULSE")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("L-CLICK  ·  FIRE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 19)
        .background(instrumentPanel)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var targetingReticle: some View {
        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.62), lineWidth: 1)
                .frame(width: 30, height: 30)
            Circle()
                .fill(Color.cyan)
                .frame(width: 3, height: 3)
                .shadow(color: .cyan, radius: 5)
            Rectangle()
                .fill(Color.cyan.opacity(0.45))
                .frame(width: 1, height: 46)
            Rectangle()
                .fill(Color.cyan.opacity(0.45))
                .frame(width: 46, height: 1)
            Circle()
                .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                .frame(width: 58, height: 58)
        }
        .shadow(color: .black.opacity(0.85), radius: 4)
    }

    private var instrumentPanel: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.09, blue: 0.13).opacity(0.96), Color(red: 0.018, green: 0.038, blue: 0.07).opacity(0.97)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.cyan.opacity(0.42), .white.opacity(0.08), .cyan.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.48), radius: 18, y: 8)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.cyan.opacity(0.23))
            .frame(width: 1, height: 31)
    }

    private func instrumentValue(label: String, value: String, suffix: String) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.48))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 19, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(suffix)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.75))
            }
        }
    }

    private func statusLamp(isActive: Bool, color: Color) -> some View {
        Circle()
            .fill(isActive ? color : Color.white.opacity(0.15))
            .frame(width: 6, height: 6)
            .shadow(color: isActive ? color.opacity(0.9) : .clear, radius: 6)
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func statusCard(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.cyan.opacity(0.85))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(instrumentPanel)
    }

    private func thrustButton(_ title: String, symbol: String, direction: Int) -> some View {
        ThrustButton(title: title, symbol: symbol, direction: direction, scene: scene)
    }
}

private struct ThrustButton: View {
    let title: String
    let symbol: String
    let direction: Int
    let scene: AsteroidsScene
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundStyle(isPressed ? Color.black : (direction > 0 ? Color.cyan : Color.orange))
        .frame(width: 75, height: 52)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isPressed ? (direction > 0 ? Color.cyan : Color.orange) : Color.white.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isPressed ? Color.white.opacity(0.65) : (direction > 0 ? Color.cyan.opacity(0.4) : Color.orange.opacity(0.38)), lineWidth: 1)
        }
        .shadow(color: isPressed ? (direction > 0 ? .cyan.opacity(0.45) : .orange.opacity(0.4)) : .clear, radius: 12)
        .scaleEffect(isPressed ? 0.94 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        scene.setThrust(direction)
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    scene.setThrust(0)
                }
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.58), value: isPressed)
        .accessibilityLabel(direction > 0 ? "Thrust" : "Brake")
    }
}

private struct SceneKitGameView: NSViewRepresentable {
    let scene: AsteroidsScene
    @Binding var hud: GameHUD

    func makeCoordinator() -> Coordinator {
        Coordinator(hud: $hud, scene: scene)
    }

    func makeNSView(context: Context) -> AsteroidsInputView {
        let view = AsteroidsInputView()
        view.scene = scene
        view.delegate = scene
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.backgroundColor = NSColor(red: 0.012, green: 0.024, blue: 0.045, alpha: 1)
        view.handleFlightKey = { [weak coordinator = context.coordinator] keyCode, isDown in
            coordinator?.handleFlightKey(keyCode, isDown: isDown)
        }
        context.coordinator.attachKeyboardMonitor(for: view)
        scene.onHUDUpdate = { [weak coordinator = context.coordinator] update in
            DispatchQueue.main.async {
                coordinator?.hud.wrappedValue = update
            }
        }
        return view
    }

    func updateNSView(_ view: AsteroidsInputView, context: Context) {
        if view.scene !== scene { view.scene = scene }
    }

    static func dismantleNSView(_ view: AsteroidsInputView, coordinator: Coordinator) {
        view.releaseMouseCapture()
        coordinator.removeKeyboardMonitor()
    }

    final class Coordinator {
        var hud: Binding<GameHUD>
        private let scene: AsteroidsScene
        private var keyboardMonitor: Any?
        private var resignObserver: NSObjectProtocol?
        private var pressedKeys: Set<UInt16> = []

        init(hud: Binding<GameHUD>, scene: AsteroidsScene) {
            self.hud = hud
            self.scene = scene
        }

        func attachKeyboardMonitor(for view: AsteroidsInputView) {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window, view.window?.isKeyWindow == true else {
                    return event
                }
                switch event.keyCode {
                case 13, 1:
                    self.handleFlightKey(event.keyCode, isDown: event.type == .keyDown)
                    return event
                case 15 where event.type == .keyDown:
                    self.scene.restart()
                    return nil
                case 53 where event.type == .keyDown:
                    view.releaseMouseCapture()
                    return nil
                default:
                    return event
                }
            }

            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: view.window,
                queue: .main
            ) { [weak self, weak view] _ in
                self?.pressedKeys.removeAll()
                self?.scene.setThrust(0)
                view?.releaseMouseCapture()
            }
        }

        func handleFlightKey(_ keyCode: UInt16, isDown: Bool) {
            guard keyCode == 13 || keyCode == 1 else { return }
            if isDown {
                pressedKeys.insert(keyCode)
            } else {
                pressedKeys.remove(keyCode)
            }
            updateThrust()
        }

        func removeKeyboardMonitor() {
            if let keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
                self.keyboardMonitor = nil
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
                self.resignObserver = nil
            }
            scene.setThrust(0)
        }

        private func updateThrust() {
            scene.setThrust(pressedKeys.contains(13) ? 1 : (pressedKeys.contains(1) ? -1 : 0))
        }
    }
}

private final class AsteroidsInputView: SCNView {
    var handleFlightKey: ((UInt16, Bool) -> Void)?
    private var hasCapturedMouse = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    deinit {
        releaseMouseCapture()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func layout() {
        super.layout()
        (scene as? AsteroidsScene)?.updateViewport(width: bounds.width, height: bounds.height)
    }

    override func mouseMoved(with event: NSEvent) {
        updateAim(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateAim(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeFirstResponder(self)
        captureMouse()
    }

    override func mouseExited(with event: NSEvent) {
        if !hasCapturedMouse { releaseMouseCapture() }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        captureMouse()
        (scene as? AsteroidsScene)?.setFiring(true)
    }

    override func mouseUp(with event: NSEvent) {
        (scene as? AsteroidsScene)?.setFiring(false)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            releaseMouseCapture()
        } else if event.keyCode == 13 || event.keyCode == 1 {
            handleFlightKey?(event.keyCode, true)
        } else if event.keyCode == 15 {
            (scene as? AsteroidsScene)?.restart()
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 13 || event.keyCode == 1 {
            handleFlightKey?(event.keyCode, false)
        } else {
            super.keyUp(with: event)
        }
    }

    func releaseMouseCapture() {
        guard hasCapturedMouse else { return }
        hasCapturedMouse = false
        NSCursor.unhide()
        let result = CGAssociateMouseAndMouseCursorPosition(1)
        if result != .success {
            NSLog("Could not release mouse capture: %d", result.rawValue)
        }
    }

    private func captureMouse() {
        guard !hasCapturedMouse, window?.isKeyWindow == true else { return }
        let associationResult = CGAssociateMouseAndMouseCursorPosition(0)
        guard associationResult == .success else {
            NSLog("Could not capture mouse: %d", associationResult.rawValue)
            return
        }
        NSCursor.hide()
        hasCapturedMouse = true
    }

    private func updateAim(with event: NSEvent) {
        (scene as? AsteroidsScene)?.updateAim(deltaX: event.deltaX, deltaY: event.deltaY)
    }
}
