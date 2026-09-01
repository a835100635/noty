import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcut recorder

/// Captures a key combination. It has to intercept `performKeyEquivalent` as well
/// as `keyDown`, or combinations that match a menu item (⌘N and friends) are
/// swallowed by the menu before the field ever sees them.
final class RecorderView: NSView {
    var onCapture: ((Shortcut) -> Void)?
    /// In-note shortcuts are matched by the note itself, so a bare key is safe.
    /// A global one without a modifier would swallow that key system-wide.
    var allowsBareKeys = false
    var shortcut: Shortcut = .none { didSet { needsDisplay = true } }
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { stop(); return }
        if event.keyCode == UInt16(kVK_Delete) {
            shortcut = .none; onCapture?(.none); stop(); return
        }
        guard let s = Shortcut.from(event: event, allowingBareKey: allowsBareKeys) else {
            NSSound.beep()
            return
        }
        shortcut = s
        onCapture?(s)
        stop()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func stop() {
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                   : NSColor.textBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor
                   : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? "请按下快捷键…" : shortcut.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: r.midX - size.width / 2,
                                            y: r.midY - size.height / 2), withAttributes: attrs)
    }
}

struct ShortcutField: NSViewRepresentable {
    let shortcut: Shortcut
    var allowsBareKeys = false
    let onChange: (Shortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.shortcut = shortcut
        v.allowsBareKeys = allowsBareKeys
        v.onCapture = onChange
        return v
    }
    func updateNSView(_ v: RecorderView, context: Context) {
        v.shortcut = shortcut
        v.allowsBareKeys = allowsBareKeys
        v.onCapture = onChange
    }
}

// MARK: - Model

final class SettingsModel: ObservableObject {
    @Published var deckStyle: DeckStyle { didSet { Settings.deckStyle = deckStyle; apply() } }
    @Published var onLeftEdge: Bool     { didSet { Settings.deckOnLeftEdge = onLeftEdge; apply() } }
    @Published var edgeWidth: Double    { didSet { Settings.edgeWidth = edgeWidth; apply() } }
    @Published var overFullScreen: Bool { didSet { Settings.showOverFullScreen = overFullScreen; apply() } }
    @Published var launchAtLogin: Bool  { didSet { Settings.launchAtLogin = launchAtLogin } }

    @Published var fontName: String     { didSet { Settings.noteFontName = fontName; apply() } }
    @Published var fontSize: Double     { didSet { Settings.noteFontSize = fontSize; apply() } }
    @Published var lineHeight: Double  { didSet { Settings.noteLineHeight = lineHeight; apply() } }
    @Published var markdown: Bool       { didSet { Settings.markdownStyling = markdown; apply() } }

    @Published var scNewNote: Shortcut  { didSet { Settings.scNewNote = scNewNote; HotKeys.shared.reload() } }
    @Published var scAllNotes: Shortcut { didSet { Settings.scAllNotes = scAllNotes; HotKeys.shared.reload() } }
    @Published var scArchive: Shortcut  { didSet { Settings.scArchive = scArchive; HotKeys.shared.reload() } }
    // Handled by the open note itself, so these need no hotkey registration.
    @Published var scArchiveNote: Shortcut { didSet { Settings.scArchiveNote = scArchiveNote } }
    @Published var scClose: Shortcut   { didSet { Settings.scClose = scClose } }
    @Published var scFind: Shortcut    { didSet { Settings.scFind = scFind } }
    @Published var scTask: Shortcut    { didSet { Settings.scTask = scTask } }
    @Published var scPin: Shortcut     { didSet { Settings.scPin = scPin } }
    @Published var scColour: Shortcut  { didSet { Settings.scColour = scColour } }
    @Published var scDelete: Shortcut  { didSet { Settings.scDelete = scDelete } }
    @Published var scBigger: Shortcut  { didSet { Settings.scBigger = scBigger } }
    @Published var scSmaller: Shortcut { didSet { Settings.scSmaller = scSmaller } }

    private var loading = true

    init() {
        deckStyle = Settings.deckStyle
        onLeftEdge = Settings.deckOnLeftEdge
        edgeWidth = Settings.edgeWidth
        overFullScreen = Settings.showOverFullScreen
        launchAtLogin = Settings.launchAtLogin
        fontName = Settings.noteFontName
        fontSize = Settings.noteFontSize
        lineHeight = Settings.noteLineHeight
        markdown = Settings.markdownStyling
        scNewNote = Settings.scNewNote
        scAllNotes = Settings.scAllNotes
        scArchive = Settings.scArchive
        scArchiveNote = Settings.scArchiveNote
        scClose = Settings.scClose
        scFind = Settings.scFind
        scTask = Settings.scTask
        scPin = Settings.scPin
        scColour = Settings.scColour
        scDelete = Settings.scDelete
        scBigger = Settings.scBigger
        scSmaller = Settings.scSmaller
        loading = false
    }

    private func apply() {
        guard !loading else { return }
        (NSApp.delegate as? AppDelegate)?.refreshDecks()
    }

    /// Warn about a combination already used by another Noty shortcut.
    func duplicate(of s: Shortcut, ignoring label: String) -> Bool {
        guard s.isSet else { return false }
        let others = [("new", scNewNote), ("all", scAllNotes), ("archive", scArchive),
                      ("archiveNote", scArchiveNote), ("close", scClose), ("find", scFind),
                      ("task", scTask), ("pin", scPin), ("colour", scColour),
                      ("delete", scDelete), ("bigger", scBigger), ("smaller", scSmaller)]
            .filter { $0.0 != label }
        return others.contains { $0.1 == s }
    }
}

// MARK: - Window

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Noty 设置"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            if LibraryWindow.shared.isOpen == false { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

// MARK: - View

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                group("快捷键", "点击输入框后按下按键；⌫ 可清除一个按键。") {
                    subhead("任意应用中")
                    shortcutRow("新建笔记", model.scNewNote, "new") { model.scNewNote = $0 }
                    shortcutRow("所有笔记", model.scAllNotes, "all") { model.scAllNotes = $0 }
                    shortcutRow("归档窗口", model.scArchive, "archive") { model.scArchive = $0 }

                    subhead("打开的笔记中").padding(.top, 4)
                    shortcutRow("关闭", model.scClose, "close", bare: true) { model.scClose = $0 }
                    shortcutRow("归档此笔记", model.scArchiveNote, "archiveNote", bare: true) { model.scArchiveNote = $0 }
                    shortcutRow("删除", model.scDelete, "delete", bare: true) { model.scDelete = $0 }
                    shortcutRow("查找笔记内容", model.scFind, "find", bare: true) { model.scFind = $0 }
                    shortcutRow("切换任务", model.scTask, "task", bare: true) { model.scTask = $0 }
                    shortcutRow("置顶", model.scPin, "pin", bare: true) { model.scPin = $0 }
                    shortcutRow("切换颜色", model.scColour, "colour", bare: true) { model.scColour = $0 }
                    shortcutRow("放大文字", model.scBigger, "bigger", bare: true) { model.scBigger = $0 }
                    shortcutRow("缩小文字", model.scSmaller, "smaller", bare: true) { model.scSmaller = $0 }

                    Text("这些快捷键仅在笔记打开时生效，因此这里可以使用不带修饰键的按键。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                group("便签栏", "便签在屏幕边缘的显示方式。") {
                    row("样式") {
                        Picker("", selection: $model.deckStyle) {
                            ForEach(DeckStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
                    }
                    row("位置") {
                        Picker("", selection: $model.onLeftEdge) {
                            Text("右侧").tag(false); Text("左侧").tag(true)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                    }
                    row("感应区域") {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("", selection: $model.edgeWidth) {
                                ForEach(Settings.edgeWidths, id: \.width) { Text($0.name).tag($0.width) }
                            }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
                            Text("指针距离边缘多远时唤醒便签栏 — \(Int(model.edgeWidth)) pt。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("在全屏应用上显示", isOn: $model.overFullScreen)
                    Toggle("登录时启动", isOn: $model.launchAtLogin)
                }

                group("笔记", "笔记中的输入和格式设置。") {
                    row("字体") {
                        Picker("", selection: $model.fontName) {
                            ForEach(Ink.faces, id: \.body) { Text($0.name).tag($0.body) }
                        }.labelsHidden().frame(width: 200)
                    }
                    row("大小") {
                        HStack(spacing: 10) {
                            Slider(value: $model.fontSize,
                                   in: Settings.fontRange.lowerBound...Settings.fontRange.upperBound,
                                   step: 0.5).frame(width: 210)
                            Text("\(model.fontSize, specifier: "%.1f") pt")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        }
                    }
                    row("内容行高") {
                        HStack(spacing: 10) {
                            Slider(value: $model.lineHeight,
                                   in: Settings.lineHeightRange.lowerBound...Settings.lineHeightRange.upperBound,
                                   step: 0.05).frame(width: 210)
                            Text("\(model.lineHeight, specifier: "%.2f") 倍")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("输入时设置 Markdown 样式", isOn: $model.markdown)
                        Text("**粗体**、*斜体*、`代码`、~~删除线~~、# 标题、> 引用。文本仍保持纯文本，仅改变显示效果。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 42)
            .padding(.bottom, 30)
        }
        .frame(width: 520, height: 620)
    }

    // MARK: pieces

    @ViewBuilder
    private func group(_ title: String, _ caption: String,
                       @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(caption).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 11) { content() }
        }
    }

    private func subhead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func row(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).font(.system(size: 12.5))
                .frame(width: 104, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func shortcutRow(_ label: String, _ value: Shortcut, _ key: String,
                             bare: Bool = false,
                             _ set: @escaping (Shortcut) -> Void) -> some View {
        HStack(spacing: 14) {
            Text(label).font(.system(size: 12.5)).frame(width: 130, alignment: .leading)
            ShortcutField(shortcut: value, allowsBareKeys: bare, onChange: set)
                .frame(width: 128, height: 26)
            if model.duplicate(of: value, ignoring: key) {
                Label("快捷键已使用", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
    }
}
