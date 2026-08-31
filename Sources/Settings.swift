import Foundation
import ServiceManagement

/// Thin UserDefaults wrapper for the handful of togglable preferences.
enum Settings {
    private static let d = UserDefaults.standard

    static var showOverFullScreen: Bool {
        get { d.object(forKey: "showOverFullScreen") as? Bool ?? false }
        set { d.set(newValue, forKey: "showOverFullScreen") }
    }

    static var deckOnLeftEdge: Bool {
        get { d.bool(forKey: "deckOnLeftEdge") }
        set { d.set(newValue, forKey: "deckOnLeftEdge") }
    }

    /// Max tabs the fan shows before collapsing the remainder into "+N".
    /// Five keeps every tab at full size instead of squeezing the deck.
    static let fanLimit = 5

    /// Body text size inside a note.
    static let fontSizes: [(name: String, size: Double)] = [
        ("小", 12), ("中", 13.5), ("大", 15.5), ("特大", 18)
    ]

    static let fontRange: ClosedRange<Double> = 10...30

    static var noteFontSize: Double {
        get {
            let v = d.double(forKey: "noteFontSize")
            return fontRange.contains(v) ? v : 13.5
        }
        set { d.set(min(max(newValue, fontRange.lowerBound), fontRange.upperBound),
                    forKey: "noteFontSize") }
    }

    /// PostScript name of the face note bodies are set in; empty means the
    /// system font. Defaults to a hand, the way a sticky note actually looks.
    static var noteFontName: String {
        get {
            if let v = d.string(forKey: "noteFontName") { return v }
            // migrate the old boolean
            let hand = d.object(forKey: "handwrittenBody") as? Bool ?? true
            return hand ? "Noteworthy-Light" : ""
        }
        set { d.set(newValue, forKey: "noteFontName") }
    }

    // MARK: Shortcuts

    private static func shortcut(_ key: String, default def: Shortcut) -> Shortcut {
        guard let data = d.data(forKey: key),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return def }
        return s
    }
    private static func setShortcut(_ key: String, _ value: Shortcut) {
        d.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// ⌥⌘N, ⌥⌘A, ⌥⌘L out of the box.
    static var scNewNote: Shortcut {
        get { shortcut("scNewNote", default: Shortcut(keyCode: 45, modifiers: 2048 | 256)) }
        set { setShortcut("scNewNote", newValue) }
    }
    static var scAllNotes: Shortcut {
        get { shortcut("scAllNotes", default: Shortcut(keyCode: 0, modifiers: 2048 | 256)) }
        set { setShortcut("scAllNotes", newValue) }
    }
    static var scArchive: Shortcut {
        get { shortcut("scArchive", default: Shortcut(keyCode: 37, modifiers: 2048 | 256)) }
        set { setShortcut("scArchive", newValue) }
    }

    // In-note shortcuts. These are matched by the open note itself rather than
    // registered globally, so a bare key like esc is safe here.
    private static let cmd: UInt32 = 256, shift: UInt32 = 512
    private static let opt: UInt32 = 2048, ctrl: UInt32 = 4096

    static var scArchiveNote: Shortcut {
        get { shortcut("scArchiveNote", default: Shortcut(keyCode: 0,  modifiers: shift | cmd)) }
        set { setShortcut("scArchiveNote", newValue) }
    }
    static var scClose: Shortcut {
        get { shortcut("scClose",       default: Shortcut(keyCode: 53, modifiers: 0)) }
        set { setShortcut("scClose", newValue) }
    }
    static var scFind: Shortcut {
        get { shortcut("scFind",        default: Shortcut(keyCode: 3,  modifiers: cmd)) }
        set { setShortcut("scFind", newValue) }
    }
    static var scTask: Shortcut {
        get { shortcut("scTask",        default: Shortcut(keyCode: 17, modifiers: cmd)) }
        set { setShortcut("scTask", newValue) }
    }
    static var scPin: Shortcut {
        get { shortcut("scPin",         default: Shortcut(keyCode: 35, modifiers: cmd)) }
        set { setShortcut("scPin", newValue) }
    }
    static var scColour: Shortcut {
        get { shortcut("scColour",      default: Shortcut(keyCode: 47, modifiers: cmd)) }
        set { setShortcut("scColour", newValue) }
    }
    static var scDelete: Shortcut {
        get { shortcut("scDelete",      default: Shortcut(keyCode: 51, modifiers: cmd)) }
        set { setShortcut("scDelete", newValue) }
    }
    static var scBigger: Shortcut {
        get { shortcut("scBigger",      default: Shortcut(keyCode: 24, modifiers: ctrl)) }
        set { setShortcut("scBigger", newValue) }
    }
    static var scSmaller: Shortcut {
        get { shortcut("scSmaller",     default: Shortcut(keyCode: 27, modifiers: ctrl)) }
        set { setShortcut("scSmaller", newValue) }
    }

    // MARK: Deck

    /// How far from the screen edge the deck notices the pointer. A wider strip
    /// is easier to hit; a narrower one stays further out of the way.
    static let edgeWidths: [(name: String, width: Double)] = [
        ("窄", 8), ("标准", 14), ("宽", 28), ("很宽", 44)
    ]

    static var edgeWidth: Double {
        get {
            let v = d.double(forKey: "edgeWidth")
            return v >= 4 ? v : 14
        }
        set { d.set(newValue, forKey: "edgeWidth") }
    }

    /// Style Markdown inline — headings, emphasis, code, quotes.
    static var markdownStyling: Bool {
        get { d.object(forKey: "markdownStyling") as? Bool ?? true }
        set { d.set(newValue, forKey: "markdownStyling") }
    }

    /// How long the deck may sit untouched before it tidies itself away.
    static let fanIdleTimeout: TimeInterval = 4
    static let noteIdleTimeout: TimeInterval = 60

    /// Labelled tabs, or bare colour chips that barely touch the screen.
    static var deckStyle: DeckStyle {
        get { DeckStyle(rawValue: d.string(forKey: "deckStyle") ?? "") ?? .tabs }
        set { d.set(newValue.rawValue, forKey: "deckStyle") }
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Noty: launch-at-login toggle failed — \(error.localizedDescription)")
            }
        }
    }
}
