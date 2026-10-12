// matrix-tile: tiles the Ghostty windows on the main screen; on ultrawide screens the browser gets a strip on the left.
// Needs Accessibility permission (inherited from Matrix.app or your terminal).
import AppKit
import ApplicationServices

let browserIDs = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                  "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"]

func windows(of app: NSRunningApplication) -> [AXUIElement] {
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &v) == .success,
          let list = v as? [AXUIElement] else { return [] }
    return list.filter { w in
        var m: CFTypeRef?, sr: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m)
        AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sr)
        AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s)
        var size = CGSize.zero
        if let s { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        return (m as? Bool) != true && (sr as? String) == (kAXStandardWindowSubrole as String) && size.width > 300
    }
}

// size → position → size, otherwise macOS pushes a window that would temporarily stick out
func place(_ w: AXUIElement, _ r: CGRect) {
    var size = r.size, pos = r.origin
    let s = AXValueCreate(.cgSize, &size)!, p = AXValueCreate(.cgPoint, &pos)!
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
}

// settings: ~/.config/matrix-mode/config  (grid=auto|4x2…, browser=0.34, gap=6)
var cfg: [String: String] = [:]
if let txt = try? String(contentsOfFile: NSHomeDirectory() + "/.config/matrix-mode/config", encoding: .utf8) {
    for line in txt.split(separator: "\n") where !line.hasPrefix("#") {
        let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if kv.count == 2 { cfg[kv[0]] = kv[1] }
    }
}

let screen = NSScreen.screens[0]
let full = screen.frame, vf = screen.visibleFrame
let area = CGRect(x: vf.minX, y: full.height - vf.maxY, width: vf.width, height: vf.height)
let gap = CGFloat(Double(cfg["gap"] ?? "") ?? 6)
let browserShare = CGFloat(Double(cfg["browser"] ?? "") ?? 0.34)

let ghostty = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.mitchellh.ghostty" }
func origin(_ w: AXUIElement) -> CGPoint {
    var v: CFTypeRef?; var p = CGPoint.zero
    AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &v)
    if let v { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    return p
}
// keep the order the windows already have (reading order), so they don't jump around
let terms = (ghostty.map(windows) ?? []).sorted {
    let a = origin($0), b = origin($1)
    return abs(a.y - b.y) > 200 ? a.y < b.y : a.x < b.x
}
var browser: AXUIElement?
for id in browserIDs {
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }),
       let w = windows(of: app).first { browser = w; break }
}

var rest = area
if let b = browser, browserShare > 0, area.width / area.height > 2.2 {
    let bw = (area.width * browserShare).rounded()
    place(b, CGRect(x: area.minX + gap, y: area.minY + gap, width: bw - 2 * gap, height: area.height - 2 * gap))
    rest = CGRect(x: area.minX + bw, y: area.minY, width: area.width - bw, height: area.height)
}

let n = terms.count
for pass in 0..<2 where n > 0 {
    if pass == 1 { usleep(350_000) }   // Ghostty resizes asynchronously, a second pass settles it
    var best = (c: 1, r: n, s: Double.infinity)
    var fixed = false
    // fixed grid: windows keep a constant size, empty slots stay black
    let g = (cfg["grid"] ?? "auto").lowercased().split(separator: "x").compactMap { Int($0) }
    // a fixed grid only when it suits this screen: every window must fit, at most half of the slots empty,
    // and slots at least 640 px wide (so 4x2 on an ultrawide becomes 2x2 on a laptop with 4 windows)
    if g.count == 2, g[0] * g[1] >= n, n * 2 > g[0] * g[1], rest.width / CGFloat(g[0]) >= 640 {
        best = (g[0], g[1], 0); fixed = true
    }
    else {
        for c in 1...n {
            let r = (n + c - 1) / c
            let s = abs(log(Double((rest.width / CGFloat(c)) / (rest.height / CGFloat(r))) / 1.45)) + 0.35 * Double(c * r - n)
            if s < best.s { best = (c, r, s) }
        }
    }
    let ch = rest.height / CGFloat(best.r)
    for (i, t) in terms.enumerated() {
        let row = i / best.c
        let inRow = fixed ? best.c : (row == best.r - 1 ? n - best.c * (best.r - 1) : best.c)
        let cw = rest.width / CGFloat(inRow), col = i - row * best.c
        place(t, CGRect(x: (rest.minX + CGFloat(col) * cw + gap / 2).rounded(),
                        y: (rest.minY + CGFloat(row) * ch + gap / 2).rounded(),
                        width: (cw - gap).rounded(), height: (ch - gap).rounded()))
    }
}
print("\(n) terminal(s)\(browser != nil ? " + browser" : "")")
