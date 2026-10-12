// matrix-hotkey: a global key that toggles Matrix mode (starts or quits Matrix.app).
// Runs permanently from a LaunchAgent. Needs Input Monitoring (macOS asks on first start).
// Key from ~/.config/matrix-mode/config:  hotkey=<keycode>  hotkey_mods=ctrl+alt+cmd
// Find a keycode with:  ~/.matrix-mode/matrix-keycode
import AppKit

let appID = "dev.claude-matrix-mode.app"
let appPath = NSHomeDirectory() + "/Applications/Matrix.app"

func readConfig() -> [String: String] {
    var c: [String: String] = [:]
    let path = NSHomeDirectory() + "/.config/matrix-mode/config"
    for line in ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n") {
        let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if kv.count == 2, !kv[0].hasPrefix("#") { c[kv[0]] = kv[1] }
    }
    return c
}

let cfg = readConfig()
let keycode = Int64(cfg["hotkey"] ?? "") ?? 46   // default: M
let wantedMods: CGEventFlags = {
    var f = CGEventFlags()
    let mods = (cfg["hotkey_mods"] ?? (cfg["hotkey"] == nil ? "ctrl+alt+cmd" : "")).lowercased()
    for m in mods.split(separator: "+") {
        switch m {
        case "ctrl", "control": f.insert(.maskControl)
        case "alt", "opt", "option": f.insert(.maskAlternate)
        case "cmd", "command": f.insert(.maskCommand)
        case "shift": f.insert(.maskShift)
        default: break
        }
    }
    return f
}()
let modMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

var last = Date.distantPast
func toggle() {
    if Date().timeIntervalSince(last) < 1.5 { return }   // a double press must not flip it on and off again
    last = Date()
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first {
        running.terminate()   // the app switches the mode off when it quits
    } else {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [appPath]
        try? p.run()
    }
}

// Only ever one copy (a restarted LaunchAgent could otherwise leave two, and one press would toggle twice)
let me = ProcessInfo.processInfo.processIdentifier
let pk = Process()
pk.executableURL = URL(fileURLWithPath: "/bin/sh")
pk.arguments = ["-c", "pgrep -x matrix-hotkey | grep -vx \(me) | xargs kill 2>/dev/null; true"]
try? pk.run(); pk.waitUntilExit()

var tapRef: CFMachPort?
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                            eventsOfInterest: 1 << CGEventType.keyDown.rawValue, callback: { _, type, ev, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tapRef { CGEvent.tapEnable(tap: tapRef, enable: true) }
    } else if ev.getIntegerValueField(.keyboardEventKeycode) == keycode,
              ev.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              ev.flags.intersection(modMask) == wantedMods {
        DispatchQueue.main.async { toggle() }
    }
    return Unmanaged.passUnretained(ev)
}, userInfo: nil)
guard let tap else {
    FileHandle.standardError.write("matrix-hotkey: cannot listen to the keyboard, allow Input Monitoring in System Settings\n".data(using: .utf8)!)
    exit(1)
}
tapRef = tap
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
