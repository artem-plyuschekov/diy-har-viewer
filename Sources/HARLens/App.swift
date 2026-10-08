import AppKit
import SwiftUI
import Combine

@main
struct HARLensApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = FileStore()
    private var window: NSWindow?
    private let recentMenu = NSMenu(title: "Недавние файлы")
    private var titleSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        showWindow()
        titleSubscription = store.$fileURL.sink { [weak self] url in
            self?.window?.title = url.map { "\($0.lastPathComponent) — HAR Lens" } ?? "HAR Lens"
            self?.window?.representedURL = url
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let filename = filenames.first {
            showWindow()
            store.open(URL(fileURLWithPath: filename))
            sender.reply(toOpenOrPrint: .success)
        } else { sender.reply(toOpenOrPrint: .cancel) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        showWindow()
        store.open(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 830),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
            newWindow.title = "HAR Lens"
            newWindow.minSize = NSSize(width: 1080, height: 600)
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = NSHostingView(rootView: ContentView(store: store))
            newWindow.center()
            newWindow.setFrameAutosaveName("HARLensMainWindow")
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMenu() {
        let main = NSMenu()
        let applicationMenu = NSMenu(title: "HAR Lens")
        applicationMenu.addItem(item("О программе HAR Lens", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Скрыть HAR Lens", #selector(NSApplication.hide(_:)), "h"))
        applicationMenu.addItem(item("Показать все", #selector(NSApplication.unhideAllApplications(_:))))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Завершить HAR Lens", #selector(NSApplication.terminate(_:)), "q"))
        add(applicationMenu, to: main)

        let file = NSMenu(title: "Файл")
        let open = item("Открыть…", #selector(chooseFile), "o")
        open.target = self
        file.addItem(open)
        let recent = NSMenuItem(title: "Недавние файлы", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        recentMenu.delegate = self
        file.addItem(recent)
        file.addItem(.separator())
        file.addItem(item("Закрыть окно", #selector(NSWindow.performClose(_:)), "w"))
        add(file, to: main)

        let edit = NSMenu(title: "Правка")
        edit.addItem(item("Копировать", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Вставить", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Выбрать всё", #selector(NSText.selectAll(_:)), "a"))
        add(edit, to: main)

        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(item("Свернуть", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item("Увеличить", #selector(NSWindow.performZoom(_:))))
        add(windowMenu, to: main)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        if store.recentURLs.isEmpty {
            let empty = NSMenuItem(title: "Нет недавних файлов", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for url in store.recentURLs {
                let entry = item(url.lastPathComponent, #selector(openRecent(_:)))
                entry.target = self
                entry.representedObject = url
                entry.toolTip = url.path
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            let clear = item("Очистить историю", #selector(clearHistory))
            clear.target = self
            menu.addItem(clear)
        }
    }

    @objc private func chooseFile() { showWindow(); store.chooseFile() }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        showWindow()
        store.open(url)
    }
    @objc private func clearHistory() { store.clearHistory() }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private func add(_ menu: NSMenu, to parent: NSMenu) {
        let entry = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        parent.addItem(entry)
    }
}
