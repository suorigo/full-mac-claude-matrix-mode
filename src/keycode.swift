// matrix-keycode: prints the keycode of the next keys you press, to pick a hotkey for the config.
import AppKit

print("Press the key you want to use (Ctrl+C to quit)…")
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                            eventsOfInterest: 1 << CGEventType.keyDown.rawValue, callback: { _, _, ev, _ in
    var mods: [String] = []
    if ev.flags.contains(.maskControl) { mods.append("ctrl") }
    if ev.flags.contains(.maskAlternate) { mods.append("alt") }
    if ev.flags.contains(.maskCommand) { mods.append("cmd") }
    if ev.flags.contains(.maskShift) { mods.append("shift") }
    print("hotkey=\(ev.getIntegerValueField(.keyboardEventKeycode))" + (mods.isEmpty ? "" : "   hotkey_mods=\(mods.joined(separator: "+"))"))
    fflush(stdout)
    return Unmanaged.passUnretained(ev)
}, userInfo: nil)
guard let tap else { print("Cannot listen to the keyboard, allow Input Monitoring for your terminal."); exit(1) }
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
