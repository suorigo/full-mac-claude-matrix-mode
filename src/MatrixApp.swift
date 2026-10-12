// Matrix.app — turns Matrix mode on (~/.matrix-mode/matrix on) and draws the falling code:
// behind the terminals where Claude is working and over the browser while you are not in it.
// Quitting it (menu bar „◉ MATRIX“ or the hotkey) turns the mode off again.
import AppKit
import IOSurface

let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:.=*+-<>¦｜")
let browserIDs: Set<String> = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                               "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"]

// Classic rain: instead of clearing, each frame darkens the canvas a bit and only draws the column heads.
final class RainView: NSView {
    private var ctx: CGContext?
    private var surface: IOSurface?
    private var drops: [CGFloat] = []
    private var speeds: [CGFloat] = []
    private let cw: CGFloat = 16, chh: CGFloat = 22
    private let fontNormal = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private let fontHead = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
    var fade: CGFloat = 0.075

    override var isFlipped: Bool { true }

    private var maskLayer: CAShapeLayer?
    private var lastMask: CGPath?
    func setMask(_ path: CGPath) {
        if let lastMask, lastMask == path { return }
        lastMask = path
        if maskLayer == nil { maskLayer = CAShapeLayer(); layer?.mask = maskLayer }
        maskLayer?.frame = bounds
        // the layer of a flipped view has its origin at the top, window rects come bottom-up
        var t = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        maskLayer?.path = path.copy(using: &t)
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    private func rebuild() {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0 else { return }
        if let c = ctx, c.width == w, c.height == h { return }
        // draw straight into an IOSurface the layer uses without copying (a 5K desktop would cost a lot of CPU otherwise)
        guard let surf = IOSurface(properties: [.width: w, .height: h, .bytesPerElement: 4,
                                                .pixelFormat: kCVPixelFormatType_32BGRA]) else { return }
        surf.lock(options: [], seed: nil)
        ctx = CGContext(data: surf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: surf.bytesPerRow,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        surf.unlock(options: [], seed: nil)
        surface = surf
        ctx?.scaleBy(x: scale, y: scale)
        ctx?.setFillColor(NSColor(red: 0.004, green: 0.027, blue: 0.012, alpha: 1).cgColor)
        ctx?.fill(CGRect(origin: .zero, size: bounds.size))
        let cols = Int(bounds.width / cw) + 1
        let rows = bounds.height / chh
        drops = (0..<cols).map { _ in CGFloat.random(in: -rows...rows) }
        speeds = (0..<cols).map { _ in CGFloat.random(in: 0.35...1.0) }
        wantsLayer = true
    }

    func step() {
        guard let ctx, let surface else { rebuild(); return }
        surface.lock(options: [], seed: nil)
        defer {
            surface.unlock(options: [], seed: nil)
            // setContentsChanged is private, but without it the layer does not pick up new IOSurface content
            if let l = layer, l.responds(to: Selector(("setContentsChanged"))), l.contents as? IOSurface === surface {
                l.perform(Selector(("setContentsChanged")))
            } else { layer?.contents = surface }
        }
        let size = bounds.size
        ctx.setFillColor(NSColor(red: 0.004, green: 0.027, blue: 0.012, alpha: fade).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        let rows = size.height / chh
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for i in 0..<drops.count {
            let prev = Int(drops[i])
            drops[i] += speeds[i]
            let row = Int(drops[i])
            if row != prev && row >= 0 {
                let y = size.height - CGFloat(row + 1) * chh   // CG draws bottom-up
                // repaint the previous head green, the new head is almost white
                draw(String(glyphs.randomElement()!), at: CGPoint(x: CGFloat(i) * cw, y: y + chh),
                     color: NSColor(red: 0.1, green: 0.85, blue: 0.35, alpha: 1), font: fontNormal)
                draw(String(glyphs.randomElement()!), at: CGPoint(x: CGFloat(i) * cw, y: y),
                     color: NSColor(red: 0.8, green: 1, blue: 0.85, alpha: 1), font: fontHead)
            }
            if drops[i] > rows && CGFloat.random(in: 0...1) > 0.975 {
                drops[i] = CGFloat.random(in: -20...0)
                speeds[i] = CGFloat.random(in: 0.35...1.0)
            }
        }
        // now and then flicker a random glyph inside a trail
        for _ in 0..<max(1, drops.count / 12) {
            let i = Int.random(in: 0..<drops.count), r = Int.random(in: 0..<max(1, Int(drops[i])))
            draw(String(glyphs.randomElement()!), at: CGPoint(x: CGFloat(i) * cw, y: size.height - CGFloat(r + 1) * chh),
                 color: NSColor(red: 0.0, green: 0.55, blue: 0.2, alpha: 0.9), font: fontNormal)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ s: String, at p: CGPoint, color: NSColor, font: NSFont) {
        // clear the cell first so glyphs do not pile up
        let r = CGRect(x: p.x, y: p.y - 4, width: cw, height: chh)
        ctx?.setFillColor(NSColor(red: 0.004, green: 0.027, blue: 0.012, alpha: 1).cgColor)
        ctx?.fill(r)
        (s as NSString).draw(at: CGPoint(x: p.x, y: p.y), withAttributes: [.font: font, .foregroundColor: color])
    }
}

// macOS would push windows below the (hidden) menu bar; we want them exactly where we put them
final class FreeWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

func makeWindow(_ frame: NSRect, level: NSWindow.Level) -> (NSWindow, RainView) {
    let w = FreeWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = level
    w.isOpaque = true
    w.backgroundColor = .black
    w.ignoresMouseEvents = true
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    let v = RainView(frame: NSRect(origin: .zero, size: frame.size))
    v.wantsLayer = true
    w.contentView = v
    return (w, v)
}

// Green frame around the focused terminal, around the whole window including the title bar.
func makeBorder() -> NSWindow {
    let w = FreeWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .floating
    w.isOpaque = false
    w.backgroundColor = .clear
    w.ignoresMouseEvents = true
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
    let v = NSView()
    v.wantsLayer = true
    v.layer?.borderWidth = 2
    v.layer?.borderColor = NSColor(red: 0.35, green: 1, blue: 0.55, alpha: 0.95).cgColor
    v.layer?.cornerRadius = 12
    v.layer?.shadowColor = NSColor(red: 0.2, green: 1, blue: 0.45, alpha: 1).cgColor
    v.layer?.shadowOpacity = 0.8
    v.layer?.shadowRadius = 6
    v.layer?.shadowOffset = .zero
    w.contentView = v
    return w
}

final class App: NSObject, NSApplicationDelegate {
    let border = makeBorder()
    let gap: CGFloat = 6
    var desktop: [(NSWindow, RainView)] = []
    var overlays: [CGWindowID: (NSWindow, RainView)] = [:]
    var item: NSStatusItem!
    var tick = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        // window tiling and the Ghostty reload need Accessibility; ask once if it is missing
        if readConfig()["via_ssh"] != "1" {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        run("on")
        for s in NSScreen.screens {
            let (w, v) = makeWindow(s.frame, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1))
            w.orderFront(nil)
            desktop.append((w, v))
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.attributedTitle = NSAttributedString(string: "◉ MATRIX",
            attributes: [.foregroundColor: NSColor(red: 0.3, green: 1, blue: 0.5, alpha: 1),
                         .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)])
        let m = NSMenu()
        m.addItem(NSMenuItem(title: "Re-tile windows", action: #selector(retile), keyEquivalent: "r"))
        let lay = NSMenuItem(title: "Terminal layout", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for g in ["auto", "2x2", "3x2", "4x2", "4x3"] {
            let it = NSMenuItem(title: g == "auto" ? "Automatic" : g.replacingOccurrences(of: "x", with: " × "),
                                action: #selector(setGrid(_:)), keyEquivalent: "")
            it.representedObject = g
            it.target = self
            it.state = g == readConfig()["grid", default: "auto"] ? .on : .off
            sub.addItem(it)
        }
        lay.submenu = sub
        m.addItem(lay)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Turn Matrix off", action: #selector(quit), keyEquivalent: "q"))
        m.items.forEach { $0.target = self }
        item.menu = m

        Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.frame() }
    }

    func frame() {
        tick += 1
        desktop.forEach { $0.1.step() }   // shows through working terminals, so it has to be smooth
        if tick % 2 == 0 { syncOverlays() }
        overlays.values.forEach { if $0.0.isVisible { $0.1.step() } }
    }

    // Cover every browser window while the browser is not in front. Clicking into it removes the cover.
    func syncOverlays() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let browserFront = browserIDs.contains(front)
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { browserIDs.contains($0.bundleIdentifier ?? "") }.map { $0.processIdentifier })
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        let mainH = NSScreen.screens[0].frame.height
        func rect(_ w: [String: Any]) -> NSRect? {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"] else { return nil }
            return NSRect(x: x, y: mainH - y - ht, width: wd, height: ht)
        }

        // rain on the desktop only behind Ghostty windows, plain black elsewhere
        let ghosttyPid = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.mitchellh.ghostty" }?.processIdentifier
        let terms = info.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == ghosttyPid
                                  && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap(rect).filter { $0.width > 300 && $0.height > 200 }
        for (dw, dv) in desktop {
            let path = CGMutablePath()
            for r in terms { path.addRect(r.offsetBy(dx: -dw.frame.minX, dy: -dw.frame.minY)) }
            dv.setMask(path)
        }

        // frame around the front Ghostty window (CGWindowList is ordered front to back)
        if front == "com.mitchellh.ghostty", let r = terms.first {
            let fr = r.insetBy(dx: -1, dy: -1)
            if border.frame != fr { border.setFrame(fr, display: true) }
            if !border.isVisible { border.orderFront(nil) }
        } else if border.isVisible {
            border.orderOut(nil)
        }

        var seen = Set<CGWindowID>()
        if !browserFront {
            for w in info {
                guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                      (w[kCGWindowLayer as String] as? Int) == 0,
                      let id = w[kCGWindowNumber as String] as? CGWindowID,
                      let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"],
                      wd > 300, ht > 200 else { continue }
                seen.insert(id)
                // stretch the cover over the gaps to the screen edges
                var rect = NSRect(x: x, y: mainH - y - ht, width: wd, height: ht)
                if let scr = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.frame {
                    rect = rect.insetBy(dx: -gap, dy: -gap).intersection(scr)
                    if rect.minX - scr.minX < 3 * gap { rect.size.width += rect.minX - scr.minX; rect.origin.x = scr.minX }
                    if scr.maxY - rect.maxY < 40 { rect.size.height = scr.maxY - rect.minY }
                    if rect.minY - scr.minY < 3 * gap { rect.size.height += rect.minY - scr.minY; rect.origin.y = scr.minY }
                }
                if overlays[id] == nil {
                    let o = makeWindow(rect, level: .normal)
                    o.0.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
                    o.0.alphaValue = 0
                    overlays[id] = o
                }
                let (ow, _) = overlays[id]!
                if ow.frame != rect { ow.setFrame(rect, display: false) }
                ow.order(.above, relativeTo: Int(id))
                // fade in by steps; the system animation got stuck halfway when restarted often
                if ow.alphaValue < 1 { ow.alphaValue = min(1, ow.alphaValue + 0.2) }
            }
        }
        for (id, o) in overlays where !seen.contains(id) {
            o.0.orderOut(nil)
            o.0.alphaValue = 0
            if !browserFront { overlays[id] = nil }
        }
    }

    @objc func retile() { run("tile") }

    let configPath = NSHomeDirectory() + "/.config/matrix-mode/config"
    func readConfig() -> [String: String] {
        var c: [String: String] = [:]
        for line in ((try? String(contentsOfFile: configPath, encoding: .utf8)) ?? "").split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, !kv[0].hasPrefix("#") { c[kv[0]] = kv[1] }
        }
        return c
    }
    @objc func setGrid(_ sender: NSMenuItem) {
        var c = readConfig()
        c["grid"] = sender.representedObject as? String
        let txt = "# Matrix mode: grid=auto|2x2|3x2|4x2|4x3, browser=share of the width for the browser (0 = leave it), gap=px, hotkey=keycode, hotkey_mods=ctrl+alt+cmd\n"
            + c.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(atPath: (configPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? txt.write(toFile: configPath, atomically: true, encoding: .utf8)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        run("tile")
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ n: Notification) { run("off", wait: true) }

    // Runs ~/.matrix-mode/matrix. With via_ssh=1 it goes through `ssh localhost`, for setups where
    // the ssh session already holds Accessibility permission (e.g. when you drive the Mac over ssh).
    func run(_ arg: String, wait: Bool = false) {
        let script = NSHomeDirectory() + "/.matrix-mode/matrix"
        let p = Process()
        if readConfig()["via_ssh"] == "1" {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", "localhost", "'\(script)' \(arg)"]
        } else {
            p.executableURL = URL(fileURLWithPath: script)
            p.arguments = [arg]
        }
        try? p.run()
        if wait { p.waitUntilExit() }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
