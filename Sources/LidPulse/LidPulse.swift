import AppKit
import SwiftUI

@main
enum LidPulseApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = LidDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class LidDelegate: NSObject, NSApplicationDelegate {
    let model = LidModel()
    private var sleepObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var signals: [DispatchSourceSignal] = []
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = MenuGlyph.image
        status.button?.setAccessibilityLabel("LidPulse")
        status.button?.toolTip = "LidPulse"
        status.button?.target = self
        status.button?.action = #selector(togglePanel)
        statusItem = status
        let host = NSHostingController(rootView: PulsePanel(model: model, openSettings: { [weak self] in self?.openSettings() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signals.append(source)
        }
        let center = NSWorkspace.shared.notificationCenter
        let sleepEvents: [(Notification.Name, LidModel.SuspensionSource, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, .display, true),
            (NSWorkspace.screensDidWakeNotification, .display, false),
            (NSWorkspace.willSleepNotification, .system, true),
            (NSWorkspace.didWakeNotification, .system, false)
        ]
        for (name, source, sleeping) in sleepEvents {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.suspend(source, sleeping) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.suspend(.lock, locked) }
            })
        }
        model.launch()
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem?.button, button.window != nil else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func openSettings() {
        popover.performClose(nil)
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: LidSettings(model: model)))
            window.title = "LidPulse"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 465, height: 505))
            window.center()
            settingsWindow = window
        }
        model.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !popover.isShown { showPanel() }
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        model.displayConfigurationChanged()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let event = AgentEvent(url: url) { model.receive(event) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.terminate()
        sleepObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        lockObservers.forEach(DistributedNotificationCenter.default().removeObserver)
    }
}
