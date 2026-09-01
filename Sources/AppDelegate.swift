import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var deckManager: DeckManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()

        deckManager = DeckManager()
        UndoToast.shared.start()

        HotKeys.shared.register(
            newNote: { [weak self] in self?.newNote() },
            allNotes: { [weak self] in self?.openAllNotes() },
            archive:  { [weak self] in self?.openArchive() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeys.shared.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Actions

    @objc func newNote() {
        let note = NoteStore.shared.create()
        deckManager.focused?.expand(note.id)
    }

    @objc func openAllNotes() { LibraryWindow.shared.show(mode: .all) }
    @objc func openSettings() { SettingsWindow.shared.show() }

    /// Re-read preferences into every deck. Settings calls this on each change.
    func refreshDecks() { deckManager.refreshAll() }
    @objc func openArchive() { LibraryWindow.shared.show(mode: .archive) }

    @objc func toggleOverFullScreen() {
        Settings.showOverFullScreen.toggle()
        deckManager.refreshAll()
    }

    @objc func setDeckStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = DeckStyle(rawValue: raw) else { return }
        Settings.deckStyle = style
        deckManager.refreshAll()
    }

    @objc func setFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        Settings.noteFontSize = size
        deckManager.refreshAll()
    }

    @objc func setLineHeight(_ sender: NSMenuItem) {
        guard let multiple = sender.representedObject as? Double else { return }
        Settings.noteLineHeight = multiple
        deckManager.refreshAll()
    }

    /// ⌃+ / ⌃- while a note is open.
    func stepFontSize(by delta: Double) {
        Settings.noteFontSize += delta
        deckManager.refreshAll()
    }

    @objc func biggerText()  { stepFontSize(by: 1.5) }
    @objc func smallerText() { stepFontSize(by: -1.5) }

    @objc func setNoteFont(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Settings.noteFontName = name
        deckManager.refreshAll()
    }

    @objc func toggleDeckEdge() {
        Settings.deckOnLeftEdge.toggle()
        deckManager.refreshAll()
    }

    @objc func toggleLaunchAtLogin() {
        Settings.launchAtLogin.toggle()
    }

    @objc func exportMarkdown()  { Transfer.export(.markdown,  notes: NoteStore.shared.notes) }
    @objc func exportPlainText() { Transfer.export(.plainText, notes: NoteStore.shared.notes) }
    @objc func exportSingleFile(){ Transfer.export(.singleFile, notes: NoteStore.shared.notes) }
    @objc func exportStickies()  { Transfer.export(.stickies,  notes: NoteStore.shared.notes) }
    @objc func importStickies()  { Transfer.importFiles() }

    @objc func checkForUpdates() { Updater.shared.checkForUpdates() }

    @objc func toggleAutoUpdates() {
        Updater.shared.automaticallyChecks.toggle()
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func showAbout() {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Noty"
        a.informativeText = """
        停靠在屏幕边缘的便签。

        ⌥⌘N  新建笔记      ⌥⌘A  所有笔记      ⌥⌘L  归档
        在笔记中：Esc 关闭，⌘F 查找，⌘. 切换颜色，⌘⌫ 删除。

        笔记保存在本地 SQLite 数据库中；正文使用 AES-GCM 加密。你的笔记不会离开这台 Mac，
        应用唯一的网络请求是检查更新（可以关闭）。
        """
        a.runModal()
    }

    // MARK: Main menu
    //
    // An accessory app draws no menu bar, but NSApp.mainMenu is still what
    // dispatches ⌘C/⌘V/⌘Z inside the note editor — without it, text editing
    // loses every standard shortcut.

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Noty", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "新建笔记", action: #selector(newNote), keyEquivalent: "n")
        appMenu.addItem(withTitle: "所有笔记", action: #selector(openAllNotes), keyEquivalent: "a")
        appMenu.addItem(withTitle: "归档", action: #selector(openArchive), keyEquivalent: "l")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "导入…", action: #selector(importStickies), keyEquivalent: "i")
        appMenu.addItem(.separator())
        let bigger = appMenu.addItem(withTitle: "放大文字", action: #selector(biggerText), keyEquivalent: "+")
        bigger.keyEquivalentModifierMask = [.control]
        let smaller = appMenu.addItem(withTitle: "缩小文字", action: #selector(smallerText), keyEquivalent: "-")
        smaller.keyEquivalentModifierMask = [.control]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Noty", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Noty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // The three global shortcuts already carry ⌥; mirror that here so the menu
        // items do not shadow ⌘N / ⌘A / ⌘L inside text fields.
        for title in ["新建笔记", "所有笔记", "归档"] {
            appMenu.item(withTitle: title)?.keyEquivalentModifierMask = [.command, .option]
        }
        for item in appMenu.items where item.action != nil
            && item.action != #selector(NSApplication.hide(_:))
            && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
