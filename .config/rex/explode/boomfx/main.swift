// boomfx: blow a Rex pane apart in 3D, over the whole screen.
//
//   boomfx --rect X,Y,W,H --ready PATH [--pid PID] [--sound PATH] [--dump PNG]
//
// --rect   The pane's place in the Rex window, as fractions of the window's layout.
// --ready  Written once the overlay covers the pane with an exact copy. The caller
//          then removes the real pane; nobody sees it go.
// --pid    The Rex app's process. Default: the frontmost window of an app named Rex*.
// --sound  Played at the boom.
// --dump   Save the captured pane to PNG and exit, for checking the crop.
// --inset  T,L,B,R points between the window's edges and its pane layout.
// --preview DIR  Don't show anything: render the whole effect off screen,
//          write frames of it to DIR as PNGs, check the copy against the
//          capture, and report slow frames. For working on the effect.
// --stats  Report readiness time, slow frames and the frame count after the
//          boom on stderr.
// --until  With --preview: stop this many seconds after ready.
// --boom   Live mode. The caller keeps the real pane until this file appears,
//          just before the boom. Until then the shaking copy shows the pane
//          live, captured from the Rex window, over a dark hole where it was.
// --livecheck  With --boom: render the still copy and the first live frame
//          off screen, report how far apart they are, and exit.
//
// Exits 2 when it can't capture the pane (no Screen Recording permission, no
// Rex window on screen). The caller then falls back to the ASCII explosion.

import AppKit
import AVFoundation
import MetalKit
import SceneKit
import ScreenCaptureKit

// MARK: - Options

struct Options {
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var ready: String?
    var pid: pid_t?
    var sound: String?
    var dump: String?
    var preview: String?
    var until = 10.0 // --until: stop a preview this many seconds after ready
    var inset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    var deadline = 1.8 // give up if not ready this many seconds after starting
    var stats = false  // --stats: print how many frames were drawn after the boom
    var boom: String?  // --boom: live mode; written when the caller should remove the pane
    var livecheck = false
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func nums(_ s: String) -> [CGFloat] { s.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) } }
    while !args.isEmpty {
        let key = args.removeFirst()
        let value = args.isEmpty ? "" : args.removeFirst()
        switch key {
        case "--rect":
            let n = nums(value)
            if n.count == 4 { o.rect = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
        case "--ready": o.ready = value
        case "--pid": o.pid = pid_t(value)
        case "--sound": o.sound = value.isEmpty ? nil : value
        case "--dump": o.dump = value
        case "--preview": o.preview = value
        case "--until": o.until = Double(value) ?? o.until
        case "--inset":
            let n = nums(value)
            if n.count == 4 { o.inset = NSEdgeInsets(top: n[0], left: n[1], bottom: n[2], right: n[3]) }
        case "--deadline": o.deadline = Double(value) ?? o.deadline
        case "--stats": o.stats = true; args.insert(value, at: 0)
        case "--boom": o.boom = value
        case "--livecheck": o.livecheck = true; args.insert(value, at: 0)
        default: break
        }
    }
    return o
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("boomfx: " + message + "\n").data(using: .utf8)!)
    exit(2)
}

// MARK: - Finding and capturing the pane

/// The frontmost on-screen Rex window: its id and its frame in global
/// top-left-origin points.
func rexWindow(pid: pid_t?) -> (CGWindowID, CGRect)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for w in list { // front to back
        guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t
        if let pid { if ownerPID != pid { continue } } else if !owner.hasPrefix("Rex") { continue }
        guard let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b), r.width > 200, r.height > 200,
              let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
        return (id, r)
    }
    return nil
}

// Accessibility: Rex shows its panes inside a group described "Split layout",
// one group per pane. Their frames place the pane exactly, sidebar and all.
func axAttr(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    AXUIElementCopyAttributeValue(e, a as CFString, &v)
    return v
}

func axFrame(_ e: AXUIElement) -> CGRect? {
    guard let p = axAttr(e, kAXPositionAttribute), let s = axAttr(e, kAXSizeAttribute) else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &origin)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

func axChildren(_ e: AXUIElement) -> [AXUIElement] { (axAttr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

/// The pane's frame from Accessibility, or nil when it isn't available.
func axPaneFrame(pid: pid_t, window: CGRect, rect: CGRect) -> CGRect? {
    let app = AXUIElementCreateApplication(pid)
    guard let w = ((axAttr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first(where: {
        guard let f = axFrame($0) else { return false }
        return abs(f.minX - window.minX) < 2 && abs(f.minY - window.minY) < 2 && abs(f.width - window.width) < 2
    }) else { return nil }
    var layout: AXUIElement?
    func find(_ e: AXUIElement, _ depth: Int) {
        if layout != nil || depth > 8 { return }
        if axAttr(e, kAXDescriptionAttribute) as? String == "Split layout" { layout = e; return }
        axChildren(e).forEach { find($0, depth + 1) }
    }
    find(w, 0)
    guard let layout, let area = axFrame(layout) else { return nil }
    let expected = CGRect(x: area.minX + rect.minX * area.width, y: area.minY + rect.minY * area.height,
                          width: rect.width * area.width, height: rect.height * area.height)
    // Snap to the pane group that overlaps the expected rect the most.
    var best: (CGRect, CGFloat)?
    func search(_ e: AXUIElement, _ depth: Int) {
        if depth > 12 { return }
        if let f = axFrame(e), f.width > 40, f.height > 40 {
            let i = f.intersection(expected)
            if !i.isNull {
                let score = (i.width * i.height) / (f.union(expected).width * f.union(expected).height)
                if score > 0.8, score > (best?.1 ?? 0) { best = (f, score) }
            }
        }
        axChildren(e).forEach { search($0, depth + 1) }
    }
    search(layout, 0)
    return best?.0 ?? expected
}

func captureWindow(_ id: CGWindowID, size: CGSize) async throws -> (CGImage, CGFloat, SCWindow) {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: { $0.windowID == id }) else { fail("Rex window not shareable") }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let scale = CGFloat(filter.pointPixelScale)
    let config = SCStreamConfiguration()
    config.width = Int(size.width * scale)
    config.height = Int(size.height * scale)
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    return (image, scale, window)
}

/// Captures the Rex window over and over while the pane shakes. Each capture
/// is a one-shot screenshot: a continuous SCStream makes macOS badge the
/// window as shared for as long as it runs. Frames are taken on the main
/// thread by the render loop, newest first.
final class LiveFeed {
    let lock = NSLock()
    var latest: CVPixelBuffer?
    var received = 0
    var running = false

    func start(window: SCWindow, pixelSize: CGSize, colorSpace: CFString?) {
        let config = SCStreamConfiguration()
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        if let colorSpace { config.colorSpaceName = colorSpace }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        running = true
        Task.detached { [self] in
            while running {
                guard let buffer = try? await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config),
                      let pixels = CMSampleBufferGetImageBuffer(buffer) else {
                    try? await Task.sleep(nanoseconds: 8_000_000)
                    continue
                }
                lock.lock()
                latest = pixels
                received += 1
                lock.unlock()
            }
        }
    }

    /// The newest frame since the last call, if any.
    func take() -> CVPixelBuffer? {
        lock.lock()
        defer { latest = nil; lock.unlock() }
        return latest
    }

    func stop() {
        running = false
    }
}

// MARK: - Geometry

/// A slab with the polygon `p` (counterclockwise, seen from +z) as its face.
/// The face and the back show `uv` of the pane image; the edges are dark.
func slab(_ p: [CGPoint], uv: [CGPoint], depth: CGFloat, face: SCNMaterial, edge: SCNMaterial) -> SCNGeometry {
    var v: [SCNVector3] = [], n: [SCNVector3] = [], t: [CGPoint] = []
    var faceIdx: [Int32] = [], edgeIdx: [Int32] = []
    let h = depth / 2, c = p.count
    for i in 0..<c { v.append(SCNVector3(p[i].x, p[i].y, h)); n.append(SCNVector3(0, 0, 1)); t.append(uv[i]) }
    for i in 1..<(c - 1) { faceIdx += [0, Int32(i), Int32(i + 1)] }
    let b = Int32(v.count)
    for i in 0..<c { v.append(SCNVector3(p[i].x, p[i].y, -h)); n.append(SCNVector3(0, 0, -1)); t.append(uv[i]) }
    for i in 1..<(c - 1) { faceIdx += [b, b + Int32(i + 1), b + Int32(i)] }
    for i in 0..<c {
        let a = p[i], q = p[(i + 1) % c]
        let nx = q.y - a.y, ny = a.x - q.x, len = max(hypot(nx, ny), 1e-6)
        let normal = SCNVector3(nx / len, ny / len, 0)
        let s = Int32(v.count)
        for corner in [SCNVector3(a.x, a.y, h), SCNVector3(q.x, q.y, h), SCNVector3(q.x, q.y, -h), SCNVector3(a.x, a.y, -h)] {
            v.append(corner); n.append(normal); t.append(.zero)
        }
        edgeIdx += [s, s + 2, s + 1, s, s + 3, s + 2]
    }
    let g = SCNGeometry(
        sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n), SCNGeometrySource(textureCoordinates: t)],
        elements: [SCNGeometryElement(indices: faceIdx, primitiveType: .triangles),
                   SCNGeometryElement(indices: edgeIdx, primitiveType: .triangles)])
    g.materials = [face, edge]
    return g
}

/// A soft round sprite: white in the middle, clear at the edge.
func sprite(size: Int = 128, ring: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let colors: [NSColor] = ring
        ? [.clear, .clear, NSColor(white: 1, alpha: 0.9), .clear]
        : [.white, NSColor(white: 1, alpha: 0.6), NSColor(white: 1, alpha: 0.15), .clear]
    let stops: [CGFloat] = ring ? [0, 0.72, 0.86, 1] : [0, 0.25, 0.6, 1]
    let gradient = NSGradient(colors: colors, atLocations: stops, colorSpace: .deviceRGB)!
    gradient.draw(in: NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)), relativeCenterPosition: .zero)
    image.unlockFocus()
    return image
}

/// A soft round glow for additive drawing: white in the middle, black at the
/// edge, opaque throughout. Adding black changes nothing, so no edge shows.
func glow(size: Int = 256, ring: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let colors: [NSColor] = ring
        ? [.black, .black, NSColor(white: 0.9, alpha: 1), .black]
        : [.white, NSColor(white: 0.55, alpha: 1), NSColor(white: 0.12, alpha: 1), .black]
    let stops: [CGFloat] = ring ? [0, 0.72, 0.86, 1] : [0, 0.25, 0.6, 1]
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    let gradient = NSGradient(colors: colors, atLocations: stops, colorSpace: .deviceRGB)!
    gradient.draw(in: NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)), relativeCenterPosition: .zero)
    image.unlockFocus()
    return image
}

/// A lumpy smoke puff: a few soft blobs, so a cloud of them doesn't read as a disc.
func puff(size: Int = 128) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let dot = sprite(size: size)
    let n = CGFloat(size)
    for _ in 0..<9 {
        let r = n * CGFloat.random(in: 0.25...0.45)
        let x = n / 2 + CGFloat.random(in: -0.2...0.2) * n - r, y = n / 2 + CGFloat.random(in: -0.2...0.2) * n - r
        dot.draw(in: NSRect(x: x, y: y, width: 2 * r, height: 2 * r), from: .zero, operation: .sourceOver, fraction: 0.35)
    }
    image.unlockFocus()
    return image
}

/// A fixed bitmap of an image. SceneKit can re-render an NSImage that was
/// drawn with lockFocus on every frame, which made frames take seconds.
func bitmap(_ image: NSImage) -> CGImage {
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

func keyframes(_ values: [Any], _ times: [NSNumber]) -> SCNParticlePropertyController {
    let a = CAKeyframeAnimation()
    a.values = values
    a.keyTimes = times
    return SCNParticlePropertyController(animation: a)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// MARK: - The explosion

final class Explosion: NSObject, MTKViewDelegate {
    // Timeline, in seconds after the overlay is ready.
    let hold = 0.12   // the caller removes the real pane
    let lift = 0.95   // pop up and shake
    var boom: Double { hold + lift }
    let end = 4.2

    let scene = SCNScene()
    let camera = SCNNode()
    let pane = SCNNode()
    let shadowLight = SCNNode()
    let paneSize: CGSize   // scene units
    let s: CGFloat         // effect scale: 1 for a pane about 6 units across
    let face: SCNMaterial
    let edge = SCNMaterial()
    let image: CGImage
    let cameraHome: SCNVector3
    let readyPath: String?
    let player: AVAudioPlayer?

    struct Shard {
        let node: SCNNode
        var velocity: SIMD3<Float>
        let spinAxis: SIMD3<Float>
        let spin: Float
    }
    var shards: [Shard] = []
    // Textures are drawn here, on the main thread: AppKit drawing isn't safe
    // on SceneKit's render thread, where explode() runs.
    let dotTexture = bitmap(sprite())
    let glowTexture = bitmap(glow())
    let ringTexture = bitmap(glow(ring: true))
    let puffTextures = (0..<2).map { _ in bitmap(puff()) }
    var start: TimeInterval?
    var last: TimeInterval = 0
    var frames = 0
    var ready = false
    var exploded = false
    var played = false
    var smoked = false
    var ending = false
    var boomFrames = 0
    var headless = false // --preview: no window, no exit at the end

    // Live mode (--boom).
    var live: LiveFeed?
    var boomPath: String?
    var liveCrop = SCNMatrix4Identity // the pane's place in a whole-window frame, as a UV transform
    var textureCache: CVMetalTextureCache?
    // The shown frame and the one before it, which the GPU may still be reading.
    // Holding more starves the stream's buffer pool, and frames stop coming.
    var liveTextures: [CVMetalTexture] = []
    var liveFrames = 0
    var signaled = false
    let signalLead = 0.1 // the caller removes the pane this long before the boom
    let hole = SCNNode()

    init(image: CGImage, center: CGPoint, size: CGSize, screen: CGSize, readyPath: String?, sound: String?) {
        self.image = image
        self.readyPath = readyPath
        self.paneSize = size
        s = min(max(max(size.width, size.height) / 6, 0.6), 2.5)
        player = sound.flatMap { try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: $0)) }
        player?.prepareToPlay()

        // 1 unit is 100 points. The camera sees exactly the screen at z = 0.
        let fov: CGFloat = 30
        let distance = (screen.height / 2) / tan(fov / 2 * .pi / 180)
        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = fov
        camera.camera!.projectionDirection = .vertical
        camera.camera!.zNear = 0.1
        camera.camera!.zFar = 500
        cameraHome = SCNVector3(screen.width / 2, screen.height / 2, distance)
        camera.position = cameraHome
        scene.rootNode.addChildNode(camera)

        face = SCNMaterial()
        face.diffuse.contents = image
        face.diffuse.magnificationFilter = .nearest
        face.diffuse.minificationFilter = .nearest
        face.diffuse.mipFilter = .none
        face.lightingModel = .constant // the face shows the pane's pixels exactly
        edge.diffuse.contents = rgba(0.10, 0.11, 0.13)
        edge.lightingModel = .constant
        edge.isDoubleSided = true

        super.init()

        // The pane, as one slab, where the real pane is.
        let w = size.width, h = size.height
        let corners = [CGPoint(x: -w / 2, y: -h / 2), CGPoint(x: w / 2, y: -h / 2), CGPoint(x: w / 2, y: h / 2), CGPoint(x: -w / 2, y: h / 2)]
        slabNode.geometry = slab(corners, uv: corners.map(uvOf), depth: 0.06, face: face, edge: edge)
        pane.addChildNode(slabNode)
        pane.position = SCNVector3(center.x, center.y, 0)
        scene.rootNode.addChildNode(pane)
        prepare()

        // An invisible floor at the screen that only shows shadows.
        let floor = SCNNode(geometry: SCNPlane(width: screen.width * 3, height: screen.height * 3))
        floor.geometry!.firstMaterial!.lightingModel = .shadowOnly
        floor.position = SCNVector3(screen.width / 2, screen.height / 2, -0.05)
        scene.rootNode.addChildNode(floor)

        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowRadius = 14
        light.shadowSampleCount = 24
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.orthographicScale = max(screen.width, screen.height) * 0.6
        light.zNear = 0.1
        light.zFar = 200
        light.shadowColor = rgba(0, 0, 0, 0)
        light.intensity = 600
        shadowLight.light = light
        shadowLight.position = SCNVector3(center.x - 3, center.y + 4, 40)
        shadowLight.look(at: SCNVector3(center.x, center.y, 0))
        scene.rootNode.addChildNode(shadowLight)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 450
        scene.rootNode.addChildNode(ambient)
    }

    func uvOf(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x + paneSize.width / 2) / paneSize.width, y: 1 - (p.y + paneSize.height / 2) / paneSize.height)
    }

    /// One step of the timeline. Called right before each frame is drawn.
    func update(_ time: TimeInterval) {
        frames += 1
        // Draw a few frames of the still copy before saying it covers the pane.
        if !ready {
            if frames >= 3 {
                ready = true
                start = time
                if let readyPath { FileManager.default.createFile(atPath: readyPath, contents: Data("ready\n".utf8)) }
                if options.stats { FileHandle.standardError.write(String(format: "boomfx: ready %.0f ms after launch\n", (Date().timeIntervalSince1970 - launched) * 1000).data(using: .utf8)!) }
            }
            last = time
            return
        }
        let t = time - start!
        let dt = Float(min(max(time - last, 0), 1.0 / 30))
        last = time

        if boomPath != nil, !signaled {
            if t >= boom - signalLead { signalBoom() } else { applyLive() }
        }
        if t < boom { shake(t) }
        if !played, t >= boom - 0.03 { played = true; player?.play() }
        if !exploded, t >= boom { explode(at: t) }
        if exploded { fly(t: t, dt: dt) }
        if !smoked, t >= boom + 0.12 { smoked = true; emit(smoke, at: t) }
        if exploded { boomFrames += 1 }
        if t >= end, !ending {
            ending = true
            if options.stats { FileHandle.standardError.write("boomfx: \(boomFrames) frames after the boom\n".data(using: .utf8)!) }
            if !headless { NSApp.terminate(nil) }
        }
    }

    // MARK: Pop up and shake

    func shake(_ t: Double) {
        guard t > hold else { return }
        let k = Float((t - hold) / lift)               // 0...1
        let ease = 1 - pow(1 - k, 3)
        let amp = 0.015 + 0.11 * k * k                // grows toward the boom
        pane.position.z = CGFloat(1.4 * ease)          // toward the viewer
        pane.position.x += CGFloat(Float.random(in: -1...1) * amp * 0.5)
        pane.position.y += CGFloat(Float.random(in: -1...1) * amp * 0.5)
        // Pull it back toward home so the jitter doesn't wander.
        let home = paneHome
        pane.position.x += (home.x - pane.position.x) * 0.35
        pane.position.y += (home.y - pane.position.y) * 0.35
        pane.eulerAngles = SCNVector3(CGFloat(Float.random(in: -1...1) * 0.07 * k - 0.05 * ease),
                                      CGFloat(Float.random(in: -1...1) * 0.07 * k + 0.04 * ease),
                                      CGFloat(Float.random(in: -1...1) * 0.045 * k))
        // It heats up just before it goes.
        let heat = CGFloat(max(0, k - 0.55) / 0.45)
        face.multiply.contents = rgba(1, 1 - 0.18 * heat, 1 - 0.35 * heat)
        shadowLight.light!.shadowColor = rgba(0, 0, 0, CGFloat(0.55 * ease))
    }

    lazy var paneHome: SCNVector3 = pane.position

    // MARK: Live

    /// Shows the newest streamed frame on the pane. The frame is the whole
    /// window; liveCrop picks the pane out of it.
    @discardableResult
    func applyLive() -> Bool {
        guard let pixels = live?.take(), let device else { return false }
        if textureCache == nil { CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) }
        guard let cache = textureCache else { return false }
        var made: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm_srgb,
                                                  CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &made)
        guard let made, let texture = CVMetalTextureGetTexture(made) else { return false }
        liveTextures.append(made)
        if liveTextures.count > 2 { liveTextures.removeFirst() }
        face.diffuse.contents = texture
        face.diffuse.contentsTransform = liveCrop
        liveFrames += 1
        return true
    }

    /// Freezes the copy on its last live frame and tells the caller to take
    /// the real pane away. The hole covers the neighbours as they move in.
    func signalBoom() {
        signaled = true
        live?.stop()
        if let boomPath { FileManager.default.createFile(atPath: boomPath, contents: Data("boom\n".utf8)) }
        if options.stats { FileHandle.standardError.write("boomfx: \(liveFrames) live frames applied, \(live?.received ?? 0) received before the boom\n".data(using: .utf8)!) }
    }

    /// A dark recess where the pane was, behind the lifted copy, so the real
    /// pane doesn't show around it.
    func addHole(color: NSColor) {
        let plane = SCNPlane(width: paneSize.width, height: paneSize.height)
        plane.firstMaterial!.diffuse.contents = color
        plane.firstMaterial!.lightingModel = .constant
        hole.geometry = plane
        hole.position = SCNVector3(pane.position.x, pane.position.y, -0.04)
        scene.rootNode.addChildNode(hole)
    }

    /// --livecheck: the still copy and the first live frame, drawn off screen
    /// in the same place, compared over the pane.
    func liveCheck(size: CGSize, pane: CGRect) {
        let (pass, target) = offscreen(size: size)
        render(to: pass, size: size, time: 0)?.waitUntilCompleted()
        let still = readback(target)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            let got = applyLive()
            SCNTransaction.commit()
            SCNTransaction.flush()
            if got { break }
        }
        print("live frames received: \(live?.received ?? 0), applied: \(liveFrames)")
        render(to: pass, size: size, time: 1.0 / 60)?.waitUntilCompleted()
        let moving = readback(target)
        var sum = 0, n = 0, worst = 0
        var y = Int(pane.minY) + 2
        while y < Int(pane.maxY) - 2 {
            var x = Int(pane.minX) + 2
            while x < Int(pane.maxX) - 2 {
                let a = (y * target.width + x) * 4
                for c in 0..<3 { let d = abs(Int(still[a + c]) - Int(moving[a + c])); sum += d; worst = max(worst, d) }
                n += 3
                x += 5
            }
            y += 5
        }
        print(String(format: "still vs live over the pane: mean diff %.2f, max %d", Double(sum) / Double(max(n, 1)), worst))
        do {
            let dir = options.preview ?? NSTemporaryDirectory()
            writePNG(still, width: target.width, height: target.height, to: dir + "/livecheck-still.png")
            writePNG(moving, width: target.width, height: target.height, to: dir + "/livecheck-live.png")
        }
    }

    // MARK: Built before the overlay shows
    //
    // Everything the boom needs is made here, on the main thread. Creating
    // SceneKit objects on the render thread, where explode() runs, stalls
    // every later frame for about a second. So does a scene change from the
    // main thread once rendering has started.

    let slabNode = SCNNode()
    var fire: SCNParticleSystem!
    var billow: SCNParticleSystem!
    var sparks: SCNParticleSystem!
    var smoke: SCNParticleSystem!
    let flash = SCNNode()
    let ring = SCNNode()

    // Every particle system is in the scene from the start, frozen (speed
    // 0), and emit() sets it running. A system added during the run takes
    // its first step over the whole scene time, so a burst meant to be one
    // sprite came out as a thousand screen-sized ones and the GPU took
    // seconds per frame. Its birth rate is fixed when it is added, so it
    // can't be parked at 0 either.
    var emitters: [SCNParticleSystem] = []

    func emit(_ system: SCNParticleSystem, at t: Double) {
        system.speedFactor = 1
    }

    /// A system that waits, frozen, for emit().
    func emitter(_ system: SCNParticleSystem, rate: CGFloat, duration: Double, z: CGFloat) {
        system.loops = false
        system.emissionDuration = CGFloat(duration)
        system.birthRate = rate
        system.speedFactor = 0
        emitters.append(system)
        scene.addParticleSystem(system, transform: SCNMatrix4MakeTranslation(pane.position.x, pane.position.y, z))
    }

    func prepare() {
        // Cut the pane into triangles on a jittered grid. The pieces start
        // hidden, as children of the pane, in exactly the place they cover.
        let w = paneSize.width, h = paneSize.height
        let rows = 5, cols = max(3, Int((5 * w / h).rounded()))
        var grid = [[CGPoint]](repeating: [], count: rows + 1)
        for r in 0...rows {
            for c in 0...cols {
                var p = CGPoint(x: -w / 2 + w * CGFloat(c) / CGFloat(cols), y: -h / 2 + h * CGFloat(r) / CGFloat(rows))
                if r > 0, r < rows { p.y += CGFloat.random(in: -0.35...0.35) * h / CGFloat(rows) }
                if c > 0, c < cols { p.x += CGFloat.random(in: -0.35...0.35) * w / CGFloat(cols) }
                grid[r].append(p)
            }
        }
        var triangles: [[CGPoint]] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let a = grid[r][c], b = grid[r][c + 1], d = grid[r + 1][c + 1], e = grid[r + 1][c]
                if Bool.random() { triangles += [[a, b, d], [a, d, e]] } else { triangles += [[a, b, e], [b, d, e]] }
            }
        }
        for tri in triangles {
            let cx = tri.map(\.x).reduce(0, +) / 3, cy = tri.map(\.y).reduce(0, +) / 3
            let local = tri.map { CGPoint(x: $0.x - cx, y: $0.y - cy) }
            let node = SCNNode(geometry: slab(local, uv: tri.map(uvOf), depth: 0.07, face: face, edge: edge))
            node.position = SCNVector3(cx, cy, 0)
            node.isHidden = true
            pane.addChildNode(node)
            // Outward from the middle, toward the viewer, and up a little.
            var out = SIMD2<Float>(Float(cx), Float(cy))
            let len = max(simd_length(out), 0.001)
            out /= len
            let reach = len / Float(max(w, h)) * 2          // edge pieces fly faster
            let speed = (2.5 + 5 * reach + Float.random(in: 0...3)) * Float(s)
            let v = SIMD3<Float>(out.x * speed, out.y * speed + Float.random(in: 1...4) * Float(s),
                                 Float.random(in: 0.3...2.5))
            let axis = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -0.4...0.4)))
            shards.append(Shard(node: node, velocity: v, spinAxis: axis, spin: Float.random(in: 4...15)))
        }

        // Fireball: a burst of glowing puffs that cool from white to red.
        fire = SCNParticleSystem()
        fire.particleImage = dotTexture
        fire.particleLifeSpan = 0.8
        fire.particleLifeSpanVariation = 0.3
        fire.emitterShape = SCNSphere(radius: 0.25 * s)
        fire.birthLocation = .volume
        fire.birthDirection = .random
        fire.particleVelocity = 2.4 * s
        fire.particleVelocityVariation = 1.4 * s
        fire.dampingFactor = 4
        fire.particleSize = 0.26 * s
        fire.particleSizeVariation = 0.12 * s
        fire.particleAngleVariation = 180
        fire.blendMode = .additive
        fire.isLightingEnabled = false
        fire.propertyControllers = [
            .size: keyframes([0.6, 1.5, 2.0], [0, 0.3, 1]),
            .color: keyframes([rgba(1, 0.97, 0.85, 1), rgba(1, 0.78, 0.32, 0.9), rgba(0.95, 0.4, 0.07, 0.7), rgba(0.55, 0.1, 0.02, 0.45), rgba(0.15, 0.03, 0.01, 0)],
                              [0, 0.12, 0.35, 0.65, 1]),
        ]
        emitter(fire, rate: 2600, duration: 0.07, z: 1.4)

        // Billow: slower, darker flame that rolls outward after the core.
        billow = SCNParticleSystem()
        billow.particleImage = puffTextures[0]
        billow.particleLifeSpan = 1.0
        billow.particleLifeSpanVariation = 0.3
        billow.emitterShape = SCNSphere(radius: 0.4 * s)
        billow.birthLocation = .volume
        billow.birthDirection = .random
        billow.particleVelocity = 1.6 * s
        billow.particleVelocityVariation = 1.0 * s
        billow.dampingFactor = 2.5
        billow.acceleration = SCNVector3(0, 0.8, 0)
        billow.particleSize = 0.45 * s
        billow.particleSizeVariation = 0.2 * s
        billow.particleAngleVariation = 180
        billow.particleAngularVelocityVariation = 90
        billow.blendMode = .additive
        billow.isLightingEnabled = false
        billow.propertyControllers = [
            .size: keyframes([0.5, 1.4, 1.9], [0, 0.35, 1]),
            .color: keyframes([rgba(1, 0.6, 0.2, 0.0), rgba(1, 0.5, 0.12, 0.7), rgba(0.7, 0.18, 0.04, 0.45), rgba(0.2, 0.04, 0.01, 0)],
                              [0, 0.15, 0.5, 1]),
        ]

        emitter(billow, rate: 900, duration: 0.12, z: 1.4)

        // Flash and shockwave: two quads facing the viewer, added onto the screen.
        func quad(_ node: SCNNode, _ image: CGImage, _ color: NSColor, z: CGFloat) {
            let plane = SCNPlane(width: 1, height: 1)
            let m = plane.firstMaterial!
            m.diffuse.contents = image
            m.multiply.contents = color
            m.lightingModel = .constant
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            node.geometry = plane
            node.position = SCNVector3(pane.position.x, pane.position.y, z)
            node.renderingOrder = 10
            node.isHidden = true
            scene.rootNode.addChildNode(node)
        }
        quad(flash, glowTexture, rgba(1, 0.92, 0.72), z: 1.6)
        quad(ring, ringTexture, rgba(1, 0.75, 0.45), z: 1.5)

        // Sparks: fast, thin streaks that fall.
        sparks = SCNParticleSystem()
        sparks.particleImage = dotTexture
        sparks.particleLifeSpan = 0.8
        sparks.particleLifeSpanVariation = 0.5
        sparks.emitterShape = SCNSphere(radius: 0.2 * s)
        sparks.birthDirection = .random
        sparks.particleVelocity = 6 * s
        sparks.particleVelocityVariation = 3.5 * s
        sparks.dampingFactor = 0.7
        sparks.acceleration = SCNVector3(0, -14, 0)
        sparks.particleSize = 0.05 * s
        sparks.stretchFactor = 0.035
        sparks.blendMode = .additive
        sparks.isLightingEnabled = false
        sparks.propertyControllers = [
            .color: keyframes([rgba(1, 1, 0.85), rgba(1, 0.8, 0.3), rgba(1, 0.35, 0.05, 0)], [0, 0.4, 1]),
        ]
        emitter(sparks, rate: 3000, duration: 0.05, z: 1.4)

        // Smoke: slower, darker puffs that rise and spread after the fire.
        smoke = SCNParticleSystem()
        smoke.particleImage = puffTextures[1]
        smoke.particleLifeSpan = 1.6
        smoke.particleLifeSpanVariation = 0.5
        smoke.emitterShape = SCNSphere(radius: 0.4 * s)
        smoke.birthLocation = .volume
        smoke.birthDirection = .random
        smoke.particleVelocity = 1.0 * s
        smoke.particleVelocityVariation = 0.9 * s
        smoke.dampingFactor = 1.3
        smoke.acceleration = SCNVector3(0, 1.3, 0)
        smoke.particleSize = 0.5 * s
        smoke.particleSizeVariation = 0.2 * s
        smoke.particleAngleVariation = 180
        smoke.particleAngularVelocity = 25
        smoke.particleAngularVelocityVariation = 40
        smoke.blendMode = .alpha
        smoke.isLightingEnabled = false
        smoke.propertyControllers = [
            .size: keyframes([0.7, 1.7, 2.4], [0, 0.4, 1]),
            .color: keyframes([rgba(0.3, 0.2, 0.14, 0), rgba(0.16, 0.14, 0.13, 0.5), rgba(0.28, 0.27, 0.26, 0.25), rgba(0.4, 0.4, 0.4, 0)],
                              [0, 0.15, 0.55, 1]),
        ]
        emitter(smoke, rate: 320, duration: 0.3, z: 1.2)
    }

    // MARK: Boom

    /// The pane whole and unlit (an exact copy), or in lit pieces.
    func boomState(_ on: Bool) {
        slabNode.isHidden = on
        for p in shards { p.node.isHidden = !on }
        face.lightingModel = on ? .lambert : .constant
        edge.lightingModel = on ? .lambert : .constant
        face.multiply.contents = nil
        face.emission.contents = NSColor.black // nil leaves the last glow in place
    }

    func explode(at t: Double) {
        exploded = true
        boomState(true)
        flash.isHidden = false
        ring.isHidden = false
        emit(fire, at: t)
        emit(billow, at: t)
        emit(sparks, at: t)
    }

    // MARK: Rendering
    //
    // One thread does everything. The scene is changed and drawn from
    // MTKView's draw callback on the main thread, through an SCNRenderer,
    // into a drawable this process acquires and presents itself. SCNView's
    // own render thread stopped getting drawables back a frame or two after
    // the boom, whatever the scene held, and nothing in it could be asked why.

    let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    let samples = 4
    var device: MTLDevice!
    var queue: MTLCommandQueue!
    var renderer: SCNRenderer!
    var lastDraw: TimeInterval = 0

    func attach(device: MTLDevice) {
        self.device = device
        queue = device.makeCommandQueue()
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false
        renderer.isPlaying = true
    }

    func step(_ time: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        update(time)
        SCNTransaction.commit()
        SCNTransaction.flush()
    }

    func render(to pass: MTLRenderPassDescriptor, size: CGSize, time: TimeInterval, drawable: MTLDrawable? = nil) -> MTLCommandBuffer? {
        guard let cb = queue.makeCommandBuffer() else { return nil }
        if options.stats {
            cb.addCompletedHandler { if let e = $0.error { FileHandle.standardError.write("boomfx: gpu error \(e)\n".data(using: .utf8)!) } }
        }
        renderer.render(atTime: time, viewport: CGRect(origin: .zero, size: size), commandBuffer: cb, passDescriptor: pass)
        if let drawable { cb.present(drawable) }
        cb.commit()
        return cb
    }

    func draw(in view: MTKView) {
        let time = CACurrentMediaTime()
        if options.stats, lastDraw > 0, time - lastDraw > 0.05 {
            FileHandle.standardError.write(String(format: "boomfx: %.0f ms frame at t=%.2f\n", (time - lastDraw) * 1000, start.map { time - $0 } ?? -1).data(using: .utf8)!)
        }
        lastDraw = time
        step(time)
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor else { return }
        _ = render(to: pass, size: view.drawableSize, time: time, drawable: drawable)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// A render pass into new textures: a multisampled color target, its
    /// resolve (readable from the CPU) and a depth buffer.
    func offscreen(size: CGSize) -> (MTLRenderPassDescriptor, MTLTexture) {
        let w = Int(size.width), h = Int(size.height)
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage, storage: MTLStorageMode) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = usage
            d.storageMode = storage
            return device.makeTexture(descriptor: d)!
        }
        let resolve = texture(pixelFormat, samples: 1, usage: [.renderTarget, .shaderRead], storage: .shared)
        let pass = MTLRenderPassDescriptor()
        if samples > 1 {
            pass.colorAttachments[0].texture = texture(pixelFormat, samples: samples, usage: .renderTarget, storage: .private)
            pass.colorAttachments[0].resolveTexture = resolve
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = resolve
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = texture(.depth32Float, samples: samples, usage: .renderTarget, storage: .private)
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        return (pass, resolve)
    }

    /// Draws the boom once, off screen, before the overlay shows, so its
    /// shaders are compiled. Compiling them at the boom cost a 140 ms frame.
    func warmUp(size: CGSize) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        explode(at: 0)
        emit(smoke, at: 0)
        fly(t: boom + 0.01, dt: 0) // the state right after the boom, without moving anything
        SCNTransaction.commit()
        SCNTransaction.flush()
        let (pass, _) = offscreen(size: size)
        // Two frames: particles are born in the second one, so their shaders compile.
        render(to: pass, size: size, time: 0)?.waitUntilCompleted()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        for p in shards { p.node.opacity = 0.5 } // the fade at the end has its own shaders
        SCNTransaction.commit()
        SCNTransaction.flush()
        render(to: pass, size: size, time: 1.0 / 60)?.waitUntilCompleted()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        for system in emitters {
            system.speedFactor = 0
            system.reset()
        }
        boomState(false)
        for p in shards { p.node.opacity = 1 }
        flash.isHidden = true
        ring.isHidden = true
        camera.position = cameraHome
        shadowLight.light!.shadowColor = rgba(0, 0, 0, 0)
        exploded = false
        SCNTransaction.commit()
        SCNTransaction.flush()
    }

    /// --preview: the whole timeline off screen at 120 steps a second, with
    /// a PNG of chosen moments, a pixel check of the copy, and slow frames.
    func preview(dir: String, size: CGSize, pane: CGRect, source: CGImage) {
        headless = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let (pass, target) = offscreen(size: size)
        let stops: [Double] = [0, 0.6, 1.0, 1.1, 1.2, 1.4, 1.8, 2.5, 3.4]
        var next = 0
        var slow: [String] = []
        var frame = 0
        while !ending {
            let time = Double(frame) / 120
            frame += 1
            step(time)
            if ending { break }
            let t0 = CACurrentMediaTime()
            guard let cb = render(to: pass, size: size, time: time) else { break }
            let encoded = CACurrentMediaTime()
            cb.waitUntilCompleted()
            let ms = (CACurrentMediaTime() - t0) * 1000
            let t = start.map { time - $0 } ?? -1
            if t > options.until { break }
            if ms > 25 {
                let line = String(format: "t=%.2f %.0f ms (cpu %.0f, gpu %.0f)", t, ms, (encoded - t0) * 1000, (cb.gpuEndTime - cb.gpuStartTime) * 1000)
                slow.append(line)
                FileHandle.standardError.write(("slow frame " + line + "\n").data(using: .utf8)!)
            }
            if let e = cb.error { print("gpu error at t=\(t): \(e)") }
            if next < stops.count, t >= stops[next] {
                let stop = stops[next]
                next += 1
                let px = readback(target)
                if stop == 0 {
                    print(compare(px, width: target.width, pane: pane, source: source))
                    writeDiff(px, width: target.width, pane: pane, source: source, to: dir + "/diff.png")
                }
                writePNG(px, width: target.width, height: target.height, to: String(format: "%@/t%.2f.png", dir, stop))
            }
        }
        print("preview: \(frame) frames; slow frames: \(slow.isEmpty ? "none" : slow.joined(separator: ", "))")
    }

    /// |copy - capture| over the pane, times 4, as a grey PNG.
    func writeDiff(_ px: [UInt8], width: Int, pane: CGRect, source: CGImage, to path: String) {
        let src = pixels(source)
        let sw = source.width, sh = source.height
        var out = [UInt8](repeating: 255, count: sw * sh * 4)
        for y in 0..<sh {
            for x in 0..<sw {
                let a = ((Int(pane.minY) + y) * width + Int(pane.minX) + x) * 4, b = (y * sw + x) * 4
                var d = 0
                for c in 0..<3 { d = max(d, abs(Int(px[a + c]) - Int(src[b + c]))) }
                let v = UInt8(min(255, d * 4))
                out[b] = v; out[b + 1] = v; out[b + 2] = v
            }
        }
        writePNG(out, width: sw, height: sh, to: path)
    }

    func readback(_ texture: MTLTexture) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        buffer.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return buffer
    }

    /// How far the drawn copy is from the capture, over the pane, in 8-bit steps.
    func compare(_ px: [UInt8], width: Int, pane: CGRect, source: CGImage) -> String {
        let src = pixels(source)
        let sw = source.width, sh = source.height
        var lines: [String] = []
        for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] {
            var sum = 0, n = 0, worst = 0, lightA = 0, lightB = 0
            var y = 2
            while y < sh - 2 {
                var x = 2
                while x < sw - 2 {
                    let a = ((Int(pane.minY) + y + dy) * width + Int(pane.minX) + x + dx) * 4, b = (y * sw + x) * 4
                    for c in 0..<3 {
                        let d = abs(Int(px[a + c]) - Int(src[b + c]))
                        sum += d
                        worst = max(worst, d)
                        lightA += Int(px[a + c])
                        lightB += Int(src[b + c])
                    }
                    n += 3
                    x += 7
                }
                y += 7
            }
            lines.append(String(format: "copy vs capture, shifted %d,%d: mean diff %.2f, max %d, mean level %.1f vs %.1f", dx, dy,
                                Double(sum) / Double(max(n, 1)), worst, Double(lightA) / Double(max(n, 1)), Double(lightB) / Double(max(n, 1))))
        }
        return lines.joined(separator: "\n")
    }

    func fly(t: Double, dt: Float) {
        let since = Float(t - boom)

        // The screen shakes for half a second.
        let jolt = 0.2 * exp(-since * 9)
        camera.position = SCNVector3(cameraHome.x + CGFloat(Float.random(in: -1...1) * jolt),
                                     cameraHome.y + CGFloat(Float.random(in: -1...1) * jolt), cameraHome.z)

        // The flash swells and fades in a fifth of a second; the ring spreads for half a second.
        let paneMax = max(paneSize.width, paneSize.height)
        let fk = CGFloat(min(since / 0.2, 1))
        flash.scale = SCNVector3(repeating: paneMax * (0.4 + 1.0 * fk))
        flash.opacity = 1 - fk
        flash.isHidden = fk >= 1
        let rk = CGFloat(min(since / 0.5, 1))
        ring.scale = SCNVector3(repeating: paneMax * (0.3 + 1.8 * (1 - pow(1 - rk, 2))))
        ring.opacity = 0.8 * (1 - rk)
        ring.isHidden = rk >= 1

        // The hole stays while the neighbours fill the space, then fades under the fire.
        hole.opacity = CGFloat(min(1, max(0, 1 - (since - 0.25) / 0.25)))

        let fade = Float(end - 0.7) - Float(boom)
        let heat = CGFloat(max(0, 1 - since / 0.35)) // the pieces glow hot right after the boom
        face.emission.contents = rgba(0.4 * heat, 0.14 * heat, 0.02 * heat)
        let opacity = CGFloat(min(1, max(0, 1 - (since - fade) / 0.7)))
        for i in shards.indices {
            var p = shards[i]
            p.velocity.y -= 16 * dt
            p.velocity *= (1 - 0.5 * dt)
            p.node.simdPosition += p.velocity * dt
            p.node.simdOrientation = simd_quatf(angle: p.spin * dt, axis: p.spinAxis) * p.node.simdOrientation
            p.node.opacity = opacity
            shards[i] = p
        }
        shadowLight.light!.shadowColor = rgba(0, 0, 0, CGFloat(0.45 * max(0, 1 - since / 0.6)))
    }
}

extension SCNVector3 {
    init(repeating v: CGFloat) { self.init(v, v, v) }
}

/// An image's pixels as BGRA, premultiplied, sRGB: the layout of the render target.
func pixels(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    data.withUnsafeMutableBytes {
        let ctx = CGContext(data: $0.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}

/// Writes BGRA pixels as a PNG over a dark grey, so a transparent frame can be looked at.
func writePNG(_ px: [UInt8], width: Int, height: Int, to path: String) {
    var data = px
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let frame = data.withUnsafeMutableBytes({ CGContext(data: $0.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)?.makeImage() }),
          let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return }
    ctx.setFillColor(CGColor(gray: 0.25, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let out = ctx.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

let launched = Date().timeIntervalSince1970
let options = parseOptions()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var explosion: Explosion?
var overlay: NSWindow?

Task { @MainActor in
    DispatchQueue.main.asyncAfter(deadline: .now() + options.deadline) {
        if explosion?.ready != true { fail("not ready in time") }
    }
    guard let (windowID, frame) = rexWindow(pid: options.pid) else { fail("no Rex window on screen") }
    let captured: (CGImage, CGFloat, SCWindow)
    do { captured = try await captureWindow(windowID, size: frame.size) } catch { fail("capture failed: \(error)") }
    let (shot, scale, scWindow) = captured

    // The pane's rect in global top-left points: from Accessibility when it is
    // available, else from its place in the layout and --inset.
    let inset = options.inset
    let layout = CGRect(x: frame.minX + inset.left, y: frame.minY + inset.top,
                        width: frame.width - inset.left - inset.right, height: frame.height - inset.top - inset.bottom)
    let ownerPID = options.pid ?? (NSWorkspace.shared.runningApplications.first { $0.localizedName?.hasPrefix("Rex") == true }?.processIdentifier ?? 0)
    let paneRect = (axPaneFrame(pid: ownerPID, window: frame, rect: options.rect)
        ?? CGRect(x: layout.minX + options.rect.minX * layout.width, y: layout.minY + options.rect.minY * layout.height,
                  width: options.rect.width * layout.width, height: options.rect.height * layout.height))
        .intersection(frame).integral
    let crop = CGRect(x: (paneRect.minX - frame.minX) * scale, y: (paneRect.minY - frame.minY) * scale,
                      width: paneRect.width * scale, height: paneRect.height * scale)
    guard let image = shot.cropping(to: crop) else { fail("crop failed") }

    if let dump = options.dump {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dump))
        print("window \(frame) pane \(paneRect)")
        exit(0)
    }

    // Cover the screen that holds the pane.
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    let cocoaCenter = CGPoint(x: paneRect.midX, y: mainHeight - paneRect.midY)
    let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) ?? NSScreen.main!
    let sf = screen.frame
    let window = NSWindow(contentRect: sf, styleMask: .borderless, backing: .buffered, defer: false)
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    // Scene units: 100 points each, origin at the screen's bottom left.
    let u: CGFloat = 100
    let center = CGPoint(x: (paneRect.midX - sf.minX) / u, y: (mainHeight - paneRect.midY - sf.minY) / u)
    let e = Explosion(image: image, center: center, size: CGSize(width: paneRect.width / u, height: paneRect.height / u),
                      screen: CGSize(width: sf.width / u, height: sf.height / u),
                      readyPath: options.ready, sound: options.sound)
    explosion = e

    let device = MTLCreateSystemDefaultDevice()!
    e.attach(device: device)
    let drawableSize = CGSize(width: sf.width * screen.backingScaleFactor, height: sf.height * screen.backingScaleFactor)
    e.warmUp(size: drawableSize)

    if let boomPath = options.boom {
        // Live mode: keep capturing the window and show it on the shaking copy.
        let feed = LiveFeed()
        let pixelSize = CGSize(width: CGFloat(shot.width), height: CGFloat(shot.height))
        // UV transform: scale to the pane's share of the window, then move to its corner.
        e.liveCrop = SCNMatrix4Mult(SCNMatrix4MakeScale(crop.width / pixelSize.width, crop.height / pixelSize.height, 1),
                                    SCNMatrix4MakeTranslation(crop.minX / pixelSize.width, crop.minY / pixelSize.height, 0))
        e.boomPath = boomPath
        // The hole is the pane's own background, darkened.
        let bg = NSBitmapImageRep(cgImage: image).colorAt(x: 3, y: 3)?.usingColorSpace(.sRGB) ?? .black
        e.addHole(color: rgba(bg.redComponent * 0.35, bg.greenComponent * 0.35, bg.blueComponent * 0.35))
        // sRGB frames match the still copy pixel for pixel, so the hand-off doesn't show.
        feed.start(window: scWindow, pixelSize: pixelSize, colorSpace: CGColorSpace.sRGB)
        e.live = feed
        if options.livecheck {
            let top = mainHeight - sf.maxY
            e.liveCheck(size: drawableSize, pane: CGRect(x: (paneRect.minX - sf.minX) * scale, y: (paneRect.minY - top) * scale,
                                                         width: paneRect.width * scale, height: paneRect.height * scale))
            exit(0)
        }
    }

    if let dir = options.preview {
        // The pane's pixels in the overlay, top-left origin.
        let top = mainHeight - sf.maxY
        let pane = CGRect(x: (paneRect.minX - sf.minX) * scale, y: (paneRect.minY - top) * scale,
                          width: paneRect.width * scale, height: paneRect.height * scale)
        e.preview(dir: dir, size: drawableSize, pane: pane, source: image)
        exit(0)
    }

    let view = MTKView(frame: NSRect(origin: .zero, size: sf.size), device: device)
    view.colorPixelFormat = e.pixelFormat
    view.depthStencilPixelFormat = .depth32Float
    view.sampleCount = e.samples
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    view.preferredFramesPerSecond = 120
    view.layer?.isOpaque = false
    view.delegate = e
    window.contentView = view
    window.orderFrontRegardless()
    overlay = window
}

app.run()
