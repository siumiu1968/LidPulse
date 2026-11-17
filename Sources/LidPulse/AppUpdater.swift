import AppKit
import Observation
import Sparkle
import os

@MainActor @Observable
final class AppUpdater: NSObject, SPUStandardUserDriverDelegate {
    private(set) var canCheck = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyInstalls = false
    private(set) var availableVersion: String?
    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    func start() {
        guard observations.isEmpty else { return }
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        ]
        controller.startUpdater()
        refresh()
    }

    private func refresh() {
        canCheck = controller.updater.canCheckForUpdates
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyInstalls = controller.updater.automaticallyDownloadsUpdates
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func setAutomaticInstalls(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    func check() {
        guard canCheck else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }
}
