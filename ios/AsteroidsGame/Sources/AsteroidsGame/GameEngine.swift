import AppKit
import AVFoundation
import SceneKit

struct GameHUD: Equatable {
    var score = 0
    var lives = 3
    var wave = 1
    var speed: CGFloat = 0
    var hasStarted = false
    var isGameOver = false
}

final class AsteroidsScene: SCNScene, SCNSceneRendererDelegate {
    var onHUDUpdate: ((GameHUD) -> Void)?

    private let shipNode = SCNNode()
    private let cameraNode = SCNNode()
    private let sound = GameSounds()
    private var asteroids: [Asteroid] = []
    private var projectiles: [Projectile] = []
    private var sparks: [Spark] = []
    private var stars: [SCNNode] = []
    private var hud = GameHUD()
    private var velocity = SCNVector3Zero
    private var yaw: CGFloat = 0
    private var pitch: CGFloat = 0
    private var thrustDirection = 0
    private var firing = false
    private var shotCooldown: TimeInterval = 0
    private var invulnerability: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var hudUpdateElapsed: TimeInterval = 0
    private var gameOver = false

    override init() {
        super.init()
        configureScene()
        resetGame()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateViewport(width: CGFloat, height: CGFloat) {
        guard width > 0, height > 0 else { return }
        cameraNode.camera?.fieldOfView = 72
    }

    func updateAim(deltaX: CGFloat, deltaY: CGFloat) {
        guard abs(deltaX) + abs(deltaY) > 0 else { return }
        yaw -= deltaX * 0.0035
        pitch = min(max(pitch - deltaY * 0.003, -1.12), 1.12)
        hud.hasStarted = true
    }

    func setThrust(_ direction: Int) {
        thrustDirection = min(max(direction, -1), 1)
        if direction != 0 { hud.hasStarted = true }
    }

    func setFiring(_ isFiring: Bool) {
        if isFiring && gameOver { resetGame() }
        firing = isFiring
        if isFiring {
            hud.hasStarted = true
            fire()
        }
    }

    func restart() {
        guard gameOver else { return }
        resetGame()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let delta = min(max(time - lastUpdate, 0), 0.05)
        lastUpdate = time
        guard delta > 0 else { return }

        if gameOver {
            updateHUD(delta)
            return
        }

        updateFlight(delta)
        updateAsteroids(delta)
        updateProjectiles(delta)
        updateSparks(delta)
        updateStars()
        updateInvulnerability(delta)

        shotCooldown = max(0, shotCooldown - delta)
        if firing && shotCooldown == 0 { fire() }
        updateSpawning()
        updateHUD(delta)
    }

    private func configureScene() {
        background.contents = NSColor(red: 0.012, green: 0.024, blue: 0.045, alpha: 1)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 72
        camera.zNear = 0.08
        camera.zFar = 500
        camera.wantsHDR = true
        camera.bloomIntensity = 0.32
        camera.bloomThreshold = 1.1
        cameraNode.camera = camera
        cameraNode.position = SCNVector3Zero
        shipNode.addChildNode(cameraNode)
        rootNode.addChildNode(shipNode)

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor(white: 0.42, alpha: 1)
        ambient.light = ambientLight
        rootNode.addChildNode(ambient)

        let keyLight = SCNNode()
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = NSColor(red: 0.58, green: 0.78, blue: 1, alpha: 1)
        keyLight.light = directionalLight
        keyLight.eulerAngles = SCNVector3(-0.45, 0.5, 0.3)
        rootNode.addChildNode(keyLight)

        makeStars()
    }

    private func makeStars() {
        for _ in 0..<440 {
            let radius = CGFloat.random(in: 0.025...0.085)
            let star = SCNNode(geometry: SCNSphere(radius: radius))
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.emission.contents = NSColor(
                calibratedRed: CGFloat.random(in: 0.48...0.82),
                green: CGFloat.random(in: 0.69...0.94),
                blue: 1,
                alpha: CGFloat.random(in: 0.4...0.9)
            )
            star.geometry?.materials = [material]
            star.position = SCNVector3(
                CGFloat.random(in: -180...180),
                CGFloat.random(in: -120...120),
                CGFloat.random(in: -180...180)
            )
            rootNode.addChildNode(star)
            stars.append(star)
        }
    }

    private func resetGame() {
        asteroids.forEach { $0.node.removeFromParentNode() }
        projectiles.forEach { $0.node.removeFromParentNode() }
        sparks.forEach { $0.node.removeFromParentNode() }
        asteroids.removeAll()
        projectiles.removeAll()
        sparks.removeAll()

        gameOver = false
        velocity = SCNVector3Zero
        yaw = 0
        pitch = 0
        thrustDirection = 0
        firing = false
        shotCooldown = 0
        invulnerability = 0
        shipNode.position = SCNVector3Zero
        shipNode.eulerAngles = SCNVector3Zero
        hud = GameHUD()
        addWave(count: 7)
        onHUDUpdate?(hud)
    }

    private func addWave(count: Int) {
        let forward = worldForward
        let right = shipNode.convertVector(SCNVector3(-1, 0, 0), to: rootNode).normalized
        let up = shipNode.convertVector(SCNVector3(0, 1, 0), to: rootNode).normalized

        for _ in 0..<count {
            let distance = CGFloat.random(in: 52...125)
            let position = shipNode.position
                + forward.scaled(by: distance)
                + right.scaled(by: CGFloat.random(in: -38...38))
                + up.scaled(by: CGFloat.random(in: -24...24))
            let drift = SCNVector3(
                CGFloat.random(in: -1.6...1.6),
                CGFloat.random(in: -1.2...1.2),
                CGFloat.random(in: -1.5...1.5)
            )
            asteroids.append(makeAsteroid(
                position: position,
                velocity: drift,
                radius: 3.2,
                generation: 2
            ))
        }
    }

    private func makeAsteroid(
        position: SCNVector3,
        velocity: SCNVector3,
        radius: CGFloat,
        generation: Int
    ) -> Asteroid {
        let node = SCNNode(geometry: Self.rockGeometry())
        node.position = position
        node.scale = SCNVector3(radius, radius * CGFloat.random(in: 0.82...1.12), radius)
        node.eulerAngles = SCNVector3(
            CGFloat.random(in: 0...CGFloat.pi),
            CGFloat.random(in: 0...CGFloat.pi),
            CGFloat.random(in: 0...CGFloat.pi)
        )
        rootNode.addChildNode(node)
        return Asteroid(node: node, velocity: velocity, radius: radius, generation: generation)
    }

    private static func rockGeometry() -> SCNGeometry {
        let goldenRatio = (1 + sqrt(5.0)) / 2
        var vertices: [SCNVector3] = [
            SCNVector3(-1, CGFloat(goldenRatio), 0), SCNVector3(1, CGFloat(goldenRatio), 0),
            SCNVector3(-1, -CGFloat(goldenRatio), 0), SCNVector3(1, -CGFloat(goldenRatio), 0),
            SCNVector3(0, -1, CGFloat(goldenRatio)), SCNVector3(0, 1, CGFloat(goldenRatio)),
            SCNVector3(0, -1, -CGFloat(goldenRatio)), SCNVector3(0, 1, -CGFloat(goldenRatio)),
            SCNVector3(CGFloat(goldenRatio), 0, -1), SCNVector3(CGFloat(goldenRatio), 0, 1),
            SCNVector3(-CGFloat(goldenRatio), 0, -1), SCNVector3(-CGFloat(goldenRatio), 0, 1)
        ].map(\.normalized)

        var faces = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
        ]

        for _ in 0..<2 {
            var midpointCache: [Edge: Int] = [:]
            var subdivided: [[Int]] = []
            for face in faces {
                let a = Self.midpoint(face[0], face[1], vertices: &vertices, cache: &midpointCache)
                let b = Self.midpoint(face[1], face[2], vertices: &vertices, cache: &midpointCache)
                let c = Self.midpoint(face[2], face[0], vertices: &vertices, cache: &midpointCache)
                subdivided += [
                    [face[0], a, c], [face[1], b, a],
                    [face[2], c, b], [a, b, c]
                ]
            }
            faces = subdivided
        }

        var points: [SCNVector3] = []
        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []
        for face in faces {
            let first = points.count
            for index in face {
                points.append(vertices[index].scaled(by: CGFloat.random(in: 0.84...1.12)))
            }
            elements.append(SCNGeometryElement(
                indices: [UInt32(first), UInt32(first + 1), UInt32(first + 2)],
                primitiveType: .triangles
            ))
            let shade = CGFloat.random(in: 0.23...0.62)
            let material = SCNMaterial()
            material.diffuse.contents = NSColor(
                calibratedRed: shade * 0.82,
                green: shade * 0.84,
                blue: shade * 0.93,
                alpha: 1
            )
            material.roughness.contents = 0.9
            materials.append(material)
        }

        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: elements)
        geometry.materials = materials
        return geometry
    }

    private static func midpoint(
        _ first: Int,
        _ second: Int,
        vertices: inout [SCNVector3],
        cache: inout [Edge: Int]
    ) -> Int {
        let edge = Edge(first, second)
        if let existing = cache[edge] { return existing }
        let index = vertices.count
        vertices.append((vertices[first] + vertices[second]).normalized)
        cache[edge] = index
        return index
    }

    private var worldForward: SCNVector3 {
        shipNode.convertVector(SCNVector3(0, 0, -1), to: rootNode).normalized
    }

    private func updateFlight(_ delta: TimeInterval) {
        let smoothing = min(1, CGFloat(delta) * 8)
        shipNode.eulerAngles.y += shortestAngle(from: shipNode.eulerAngles.y, to: yaw) * smoothing
        shipNode.eulerAngles.x += shortestAngle(from: shipNode.eulerAngles.x, to: pitch) * smoothing
        shipNode.eulerAngles.z += shortestAngle(from: shipNode.eulerAngles.z, to: -yaw * 0.22) * smoothing

        let forward = worldForward
        let step = CGFloat(delta)
        if thrustDirection > 0 {
            velocity = velocity + forward.scaled(by: 24 * step)
        } else if thrustDirection < 0 {
            let speed = velocity.length
            velocity = speed > 0.01
                ? velocity.scaled(by: max(0, 1 - 3.5 * step))
                : SCNVector3Zero
        } else {
            velocity = velocity.scaled(by: max(0, 1 - 0.018 * step))
        }

        if velocity.length > 36 {
            velocity = velocity.normalized.scaled(by: 36)
        }
        shipNode.position = shipNode.position + velocity.scaled(by: step)
    }

    private func updateAsteroids(_ delta: TimeInterval) {
        let step = CGFloat(delta)
        for index in asteroids.indices {
            let asteroid = asteroids[index]
            asteroid.node.position = asteroid.node.position + asteroid.velocity.scaled(by: step)
            asteroid.node.eulerAngles.x += step * 0.18
            asteroid.node.eulerAngles.y += step * 0.23
            asteroid.node.eulerAngles.z += step * 0.11
            wrap(asteroid.node, radius: asteroid.radius)

            if asteroid.node.position.distance(to: shipNode.position) < asteroid.radius * 0.72,
               invulnerability == 0 {
                damageShip(asteroid)
                return
            }
        }
    }

    private func updateProjectiles(_ delta: TimeInterval) {
        var projectileIndex = projectiles.count - 1
        while projectileIndex >= 0 {
            let previous = projectiles[projectileIndex].node.position
            let direction = projectiles[projectileIndex].direction
            let distance = projectiles[projectileIndex].speed * CGFloat(delta)
            let current = previous + direction.scaled(by: distance)
            projectiles[projectileIndex].node.position = current
            projectiles[projectileIndex].remaining -= delta
            var hitAsteroid: Int?

            for asteroidIndex in asteroids.indices.reversed() {
                let asteroid = asteroids[asteroidIndex]
                if distanceSquared(from: asteroid.node.position, toSegmentFrom: previous, to: current)
                    < pow(asteroid.radius * 0.88, 2) {
                    hitAsteroid = asteroidIndex
                    break
                }
            }

            if let hitAsteroid {
                projectiles[projectileIndex].node.removeFromParentNode()
                projectiles.remove(at: projectileIndex)
                destroyAsteroid(at: hitAsteroid)
            } else if projectiles[projectileIndex].remaining <= 0 {
                projectiles[projectileIndex].node.removeFromParentNode()
                projectiles.remove(at: projectileIndex)
            }
            projectileIndex -= 1
        }
    }

    private func fire() {
        guard !gameOver else { return }
        let direction = worldForward
        let origin = shipNode.position + direction.scaled(by: 2)
        for offset: CGFloat in [-0.14, 0.14] {
            let beam = SCNNode(geometry: SCNBox(width: 0.075, height: 0.075, length: 2.3, chamferRadius: 0.03))
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor.cyan
            material.emission.contents = NSColor(red: 0.52, green: 1, blue: 1, alpha: 1)
            beam.geometry?.materials = [material]
            beam.position = origin + shipNode.convertVector(SCNVector3(offset, 0, 0), to: rootNode)
            beam.orientation = shipNode.presentation.orientation
            rootNode.addChildNode(beam)
            projectiles.append(Projectile(node: beam, direction: direction, speed: 90, remaining: 1.7))
        }
        shotCooldown = 0.17
        sound.playLaser()
    }

    private func destroyAsteroid(at index: Int) {
        let asteroid = asteroids.remove(at: index)
        let position = asteroid.node.position
        asteroid.node.removeFromParentNode()
        makeExplosion(at: position, radius: asteroid.radius)
        sound.playExplosion()
        hud.score += [20, 50, 100][asteroid.generation]

        if asteroid.generation > 0 {
            let childCount = asteroid.generation == 2 ? 4 : 2
            for _ in 0..<childCount {
                let direction = SCNVector3(
                    CGFloat.random(in: -1...1),
                    CGFloat.random(in: -1...1),
                    CGFloat.random(in: -1...1)
                ).normalized
                let velocity = asteroid.velocity.scaled(by: 0.35)
                    + direction.scaled(by: CGFloat.random(in: 1.2...2.3))
                let childPosition = position + direction.scaled(by: asteroid.radius * 0.36)
                asteroids.append(makeAsteroid(
                    position: childPosition,
                    velocity: velocity,
                    radius: asteroid.radius * (asteroid.generation == 2 ? 0.48 : 0.53),
                    generation: asteroid.generation - 1
                ))
            }
        }
    }

    private func makeExplosion(at position: SCNVector3, radius: CGFloat) {
        for index in 0..<min(32, max(14, Int(radius * 8))) {
            let spark = SCNNode(geometry: SCNSphere(radius: CGFloat.random(in: 0.055...0.14)))
            let material = SCNMaterial()
            material.lightingModel = .constant
            let color = index.isMultiple(of: 3)
                ? NSColor.cyan
                : NSColor(red: 1, green: CGFloat.random(in: 0.42...0.9), blue: 0.16, alpha: 1)
            material.diffuse.contents = color
            material.emission.contents = color
            spark.geometry?.materials = [material]
            spark.position = position
            rootNode.addChildNode(spark)
            let direction = SCNVector3(
                CGFloat.random(in: -1...1),
                CGFloat.random(in: -1...1),
                CGFloat.random(in: -1...1)
            ).normalized
            sparks.append(Spark(
                node: spark,
                velocity: direction.scaled(by: CGFloat.random(in: 3...9) * min(radius, 2)),
                remaining: Double.random(in: 0.35...0.85)
            ))
        }
    }

    private func updateSparks(_ delta: TimeInterval) {
        var index = sparks.count - 1
        while index >= 0 {
            sparks[index].remaining -= delta
            if sparks[index].remaining <= 0 {
                sparks[index].node.removeFromParentNode()
                sparks.remove(at: index)
            } else {
                sparks[index].node.position = sparks[index].node.position
                    + sparks[index].velocity.scaled(by: CGFloat(delta))
                sparks[index].node.opacity = CGFloat(min(1, sparks[index].remaining * 2))
            }
            index -= 1
        }
    }

    private func updateStars() {
        let shipPosition = shipNode.position
        for star in stars {
            if abs(star.position.x - shipPosition.x) > 175 {
                star.position.x = shipPosition.x + (star.position.x < shipPosition.x ? 350 : -350)
            }
            if abs(star.position.y - shipPosition.y) > 120 {
                star.position.y = shipPosition.y + (star.position.y < shipPosition.y ? 240 : -240)
            }
            if abs(star.position.z - shipPosition.z) > 175 {
                star.position.z = shipPosition.z + (star.position.z < shipPosition.z ? 350 : -350)
            }
        }
    }

    private func updateInvulnerability(_ delta: TimeInterval) {
        invulnerability = max(0, invulnerability - delta)
    }

    private func damageShip(_ asteroid: Asteroid) {
        asteroid.node.removeFromParentNode()
        asteroids.removeAll { $0.node === asteroid.node }
        makeExplosion(at: shipNode.position + worldForward.scaled(by: 3), radius: 2.3)
        sound.playExplosion()
        hud.lives -= 1
        velocity = SCNVector3Zero
        invulnerability = 2
        if hud.lives <= 0 {
            gameOver = true
            hud.isGameOver = true
            firing = false
        }
    }

    private func updateSpawning() {
        guard asteroids.isEmpty else { return }
        hud.wave += 1
        addWave(count: min(5 + hud.wave, 12))
    }

    private func updateHUD(_ delta: TimeInterval) {
        hud.speed = velocity.length
        hudUpdateElapsed += delta
        if hudUpdateElapsed >= 0.06 {
            hudUpdateElapsed = 0
            onHUDUpdate?(hud)
        }
    }

    private func wrap(_ node: SCNNode, radius: CGFloat) {
        let range: CGFloat = 145 + radius
        for axis in 0..<3 {
            switch axis {
            case 0:
                let offset = node.position.x - shipNode.position.x
                if offset < -range { node.position.x += range * 2 }
                if offset > range { node.position.x -= range * 2 }
            case 1:
                let offset = node.position.y - shipNode.position.y
                if offset < -range { node.position.y += range * 2 }
                if offset > range { node.position.y -= range * 2 }
            default:
                let offset = node.position.z - shipNode.position.z
                if offset < -range { node.position.z += range * 2 }
                if offset > range { node.position.z -= range * 2 }
            }
        }
    }

    private func shortestAngle(from current: CGFloat, to target: CGFloat) -> CGFloat {
        atan2(sin(target - current), cos(target - current))
    }

    private func distanceSquared(from point: SCNVector3, toSegmentFrom start: SCNVector3, to end: SCNVector3) -> CGFloat {
        let segment = end - start
        let lengthSquared = segment.dot(segment)
        guard lengthSquared > 0 else { return (point - start).dot(point - start) }
        let t = min(max((point - start).dot(segment) / lengthSquared, 0), 1)
        let closest = start + segment.scaled(by: t)
        let difference = point - closest
        return difference.dot(difference)
    }
}

private struct Asteroid {
    let node: SCNNode
    let velocity: SCNVector3
    let radius: CGFloat
    let generation: Int
}

private struct Projectile {
    let node: SCNNode
    let direction: SCNVector3
    let speed: CGFloat
    var remaining: TimeInterval
}

private struct Spark {
    let node: SCNNode
    let velocity: SCNVector3
    var remaining: TimeInterval
}

private struct Edge: Hashable {
    let low: Int
    let high: Int

    init(_ first: Int, _ second: Int) {
        low = min(first, second)
        high = max(first, second)
    }
}

private extension SCNVector3 {
    var normalized: SCNVector3 {
        let length = self.length
        guard length > 0 else { return self }
        return scaled(by: 1 / length)
    }

    var length: CGFloat {
        sqrt(x * x + y * y + z * z)
    }

    func distance(to other: SCNVector3) -> CGFloat {
        (self - other).length
    }

    func dot(_ other: SCNVector3) -> CGFloat {
        x * other.x + y * other.y + z * other.z
    }

    func scaled(by factor: CGFloat) -> SCNVector3 {
        SCNVector3(x * factor, y * factor, z * factor)
    }

    static func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        SCNVector3(left.x + right.x, left.y + right.y, left.z + right.z)
    }

    static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        SCNVector3(left.x - right.x, left.y - right.y, left.z - right.z)
    }
}

private final class GameSounds: NSObject, AVAudioPlayerDelegate {
    private let laserAudio = GameSounds.makeWave(duration: 0.22, laser: true)
    private let explosionAudio = GameSounds.makeWave(duration: 0.42, laser: false)
    private var players: [AVAudioPlayer] = []

    func playLaser() {
        play(laserAudio)
    }

    func playExplosion() {
        play(explosionAudio)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        players.removeAll { $0 === player }
    }

    private func play(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            players.append(player)
            player.play()
        } catch {
            NSLog("Could not play game sound: %@", error.localizedDescription)
        }
    }

    private static func makeWave(duration: Double, laser: Bool) -> Data {
        let sampleRate = 22_050
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = Data(capacity: sampleCount * MemoryLayout<Int16>.size)
        var noise: UInt32 = 0xA53C_9E17

        for index in 0..<sampleCount {
            let progress = Double(index) / Double(sampleCount)
            let envelope: Double
            let value: Double
            if laser {
                envelope = pow(1 - progress, 1.3)
                let frequency = 1250 - progress * 920
                value = sin(2 * .pi * frequency * progress * duration)
                    + 0.24 * sin(2 * .pi * frequency * 0.51 * progress * duration)
            } else {
                envelope = pow(1 - progress, 3.2)
                noise = 1_664_525 &* noise &+ 1_013_904_223
                let whiteNoise = Double(noise & 0xFFFF) / 32_767.5 - 1
                let rumble = sin(2 * .pi * (86 - 58 * progress) * progress * duration)
                value = whiteNoise * 0.74 + rumble * 0.48
            }
            let sample = Int16(max(-1, min(1, value * envelope * 0.8)) * Double(Int16.max))
            var littleEndian = sample.littleEndian
            Swift.withUnsafeBytes(of: &littleEndian) { samples.append(contentsOf: $0) }
        }

        var wave = Data()
        wave.append(contentsOf: Array("RIFF".utf8))
        wave.appendLE(UInt32(36 + samples.count))
        wave.append(contentsOf: Array("WAVEfmt ".utf8))
        wave.appendLE(UInt32(16))
        wave.appendLE(UInt16(1))
        wave.appendLE(UInt16(1))
        wave.appendLE(UInt32(sampleRate))
        wave.appendLE(UInt32(sampleRate * 2))
        wave.appendLE(UInt16(2))
        wave.appendLE(UInt16(16))
        wave.append(contentsOf: Array("data".utf8))
        wave.appendLE(UInt32(samples.count))
        wave.append(samples)
        return wave
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
