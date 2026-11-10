import AppKit
import Foundation
import Observation
import ServiceManagement
import os

enum LidMode: String, CaseIterable, Identifiable {
    case system, steady, breathe, music, agents, dark
    var id: Self { self }
    func title(_ language: Language) -> String {
        switch self {
        case .system: language.text("跟隨系統", "Follow System")
        case .steady: language.text("長亮", "Steady")
        case .breathe: language.text("呼吸", "Breathe")
        case .music: language.text("音樂節拍", "Music")
        case .agents: language.text("AI 狀態", "Agents")
        case .dark: language.text("熄燈", "Logo Off")
        }
    }
    var icon: String {
        switch self {
        case .system: "display"
        case .steady: "sun.max"
        case .breathe: "waveform.path"
        case .music: "music.note"
        case .agents: "terminal"
        case .dark: "moon"
        }
    }
}

@MainActor @Observable
final class LidModel {
    enum SuspensionSource { case display, system, lock }

    private(set) var mode: LidMode = .system
    private(set) var output = 0.0
    private var notice: LocalizedNotice?
    private var focus: Focus?
    private var lastSignal: AgentEvent?
    private(set) var fullRange = false
    private(set) var ownsBrightnessOverride = false
    private(set) var changingLimit = false
    private(set) var keepLogoWhenLidClosed = false
    private var closedLidFailed = false
    var language: Language = .cantonese {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }
    var message: String? {
        if let notice { return notice.text(language) }
        if closedLidFailed {
            return language.text("未能喺合蓋時控制 Logo 燈。", "Could not control the logo light with the lid closed.")
        }
        return nil
    }
    var agentStatus: String {
        guard let focus else { return language.text("等緊 Claude Code 或 Codex", "Waiting for Claude Code or Codex") }
        return statusText(focus.agent, focus.phase)
    }
    var lastEvent: String? { lastSignal.map { statusText($0.agent, $0.phase) } }

    private struct Focus: Equatable { let agent: Agent; let phase: AgentPhase }
    private(set) var loginStatus: SMAppService.Status = .notRegistered
    private(set) var installed: [Agent: Bool] = [:]
    private(set) var folders: [Agent: URL] = [:]

    var brightness: Double = 0.34 { didSet { defaults.set(brightness, forKey: "brightness"); tick() } }
    var breathePeriod: Double = 4 { didSet { defaults.set(breathePeriod, forKey: "breathePeriod") } }
    var musicSensitivity: Double = 0.55 { didSet { defaults.set(musicSensitivity, forKey: "musicSensitivity") } }
    var darkBetweenBeats = false { didSet { defaults.set(darkBetweenBeats, forKey: "darkBetweenBeats") } }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let audio = AudioMeter()
    private var driver: LogoDriver?
    @ObservationIgnored private let recoveryURL: URL
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lidHandoff: Task<Void, Never>?
    @ObservationIgnored private var started = 0.0
    @ObservationIgnored private var audioRetry = false
    @ObservationIgnored private var displayAsleep = false
    @ObservationIgnored private var systemAsleep = false
    @ObservationIgnored private var locked = false
    @ObservationIgnored private var lidClosed = false
    @ObservationIgnored private var sessions: [String: Session] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "local.lidpulse", category: "controller")

    private struct Session {
        let agent: Agent
        let phase: AgentPhase
        let time: Double
    }

    var supported: Bool { driver != nil }
    var supportsClosedLid: Bool { driver?.supportsClosedLid == true }
    var canChangeLimit: Bool { supported && !changingLimit && (!fullRange || ownsBrightnessOverride) }

    private func statusText(_ agent: Agent, _ phase: AgentPhase) -> String {
        switch phase {
        case .working: agent.title + language.text(" 處理緊", " is working")
        case .attention: agent.title + language.text(" 等你回應", " needs your attention")
        case .idle: agent.title + language.text(" 已完成", " finished")
        }
    }

    var summary: String {
        if !supported { return language.text("未偵測到可控制嘅 Logo 燈", "No supported logo light detected") }
        switch mode {
        case .system: return language.text("已停用 · Logo 跟隨系統", "Off · Logo follows the system")
        case .agents: return agentStatus
        case .dark: return language.text("Logo 已熄燈", "Logo is dark")
        default: return mode.title(language)
        }
    }

    func setEnabled(_ enabled: Bool) {
        let previous = defaults.string(forKey: "lastEffect").flatMap(LidMode.init(rawValue:)) ?? .steady
        select(enabled ? previous : .system)
    }

    private var time: Double { ProcessInfo.processInfo.systemUptime }
    private var competingApp: Bool { driver?.hasOtherOverride == true }
    private var suspended: Bool {
        systemAsleep || (!lidClosed && (displayAsleep || locked))
    }

    init(recovery: URL? = nil) {
        let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LidPulse/original-logo.plist")
        recoveryURL = recovery ?? data
        driver = LogoDriver(recovery: recoveryURL)
        language = defaults.string(forKey: "language").flatMap(Language.init(rawValue:)) ?? .cantonese
        if defaults.object(forKey: "brightness") != nil { brightness = min(1, max(0.01, defaults.double(forKey: "brightness"))) }
        if defaults.object(forKey: "breathePeriod") != nil { breathePeriod = min(9, max(2, defaults.double(forKey: "breathePeriod"))) }
        if defaults.object(forKey: "musicSensitivity") != nil { musicSensitivity = min(1, max(0, defaults.double(forKey: "musicSensitivity"))) }
        darkBetweenBeats = defaults.bool(forKey: "darkBetweenBeats")
        keepLogoWhenLidClosed = defaults.bool(forKey: "keepLogoWhenLidClosed")
        for agent in Agent.allCases {
            folders[agent] = defaults.string(forKey: agent.rawValue + "Folder").map { URL(fileURLWithPath: $0) } ?? agent.folder
        }
        refresh()
    }

    func launch(restoreMode: Bool = true) {
        if competingApp {
            notice = .init("Logo 正由另一個燈控程式控制。請先退出嗰個程式。", "Another app is controlling the logo. Quit it before using LidPulse.")
            return
        }
        if let driver, !driver.restore() {
            notice = .init("未能還原 Logo 設定。請退出其他燈控 App，再試一次。", "Could not restore the logo settings. Quit other logo apps and try again.")
            return
        }
        if restoreMode, let saved = defaults.string(forKey: "mode").flatMap(LidMode.init(rawValue:)), (saved != .music || defaults.bool(forKey: "musicActivated")) {
            select(saved)
        }
    }

    func select(_ newMode: LidMode) {
        notice = nil
        if newMode != .system {
            guard supported else { notice = .init("呢部 Mac 未偵測到可控制嘅 Logo 燈。", "This Mac has no supported logo light."); return }
            guard !competingApp else { notice = .init("Logo 正由另一個燈控程式控制。請先退出嗰個程式。", "Another app is controlling the logo. Quit it before using LidPulse."); return }
        }
        audio.stop()
        timer?.invalidate()
        timer = nil
        mode = newMode
        refreshLidState()
        defaults.set(newMode.rawValue, forKey: "mode")
        if newMode != .dark && newMode != .system { defaults.set(newMode.rawValue, forKey: "lastEffect") }
        started = time
        audioRetry = false
        if newMode == .system {
            output = 0
            driver?.releaseClosedLid()
            if !competingApp, driver?.restore() == false { notice = .init("未能還原 Logo 設定。請重新開關 LidPulse 再試。", "Could not restore the logo settings. Toggle LidPulse and try again.") }
            return
        }
        if !suspended && newMode == .music && !startAudio() { return }
        let tickTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tickTimer.tolerance = 0.008
        RunLoop.main.add(tickTimer, forMode: .common)
        timer = tickTimer
        tick()
    }

    private func startAudio() -> Bool {
        do { try audio.start(); return true }
        catch {
            let code = (error as? AudioMeter.Failure).map { " (\($0.status))" } ?? ""
            notice = .init("未能擷取系統音訊\(code)。請檢查「私隱與保安 → 螢幕與系統音訊錄製」。",
                           "System audio is unavailable\(code). Check Privacy & Security → Screen & System Audio Recording.")
            output = 0
            _ = driver?.restore()
            return false
        }
    }

    private func tick(force: Bool = false) {
        guard mode != .system, let driver else { return }
        let wasSuspended = suspended
        refreshLidState()
        guard updateSuspension(wasSuspended: wasSuspended) else { return }
        let now = time
        let elapsed = now - started
        let level: Double
        switch mode {
        case .system: return
        case .steady: level = 1
        case .breathe: level = 0.06 + 0.94 * (1 - cos(2 * .pi * elapsed / breathePeriod)) / 2
        case .music:
            let reading = audio.reading
            if reading.buffers == 0, elapsed > 2, !audioRetry {
                notice = .init("未收到系統音訊。請允許音訊擷取後，再按「音樂節拍」。", "No system audio received. Allow audio capture, then select Music again.")
                audioRetry = true
            } else if reading.buffers > 0, audioRetry {
                notice = nil
                audioRetry = false
            }
            if reading.energy > 0.001, !defaults.bool(forKey: "musicActivated") {
                defaults.set(true, forKey: "musicActivated")
            }
            let envelope = exp(-max(0, now - reading.lastBeat) / (0.13 + musicSensitivity * 0.09))
            let floor = darkBetweenBeats ? 0.0 : 0.045
            let beat = envelope * min(1, reading.beatStrength * (0.62 + musicSensitivity))
            level = floor + (1 - floor) * (beat < 0.01 ? 0 : beat)
        case .agents:
            let expired = sessions.filter { now - $0.value.time >= 3600 }.keys
            for key in expired { sessions.removeValue(forKey: key) }
            if let current = sessions.values.filter({ $0.phase == .attention }).max(by: { $0.time < $1.time }) {
                updateFocus(Focus(agent: current.agent, phase: .attention))
                let phase = (now - current.time).truncatingRemainder(dividingBy: 1.8)
                level = phase < 0.14 || (phase >= 0.29 && phase < 0.43) ? 1 : 0.035
            } else if let current = sessions.values.max(by: { $0.time < $1.time }) {
                updateFocus(Focus(agent: current.agent, phase: .working))
                let period = current.agent == .codex ? 1.25 : 2.2
                level = 0.13 + 0.87 * (1 + cos(2 * .pi * (now - current.time) / period)) / 2
            } else {
                updateFocus(nil)
                level = 0.09
            }
        case .dark: level = 0
        }
        let drive = brightness * level
        // Map the slider to the LED’s available range with finer control near darkness.
        let nits = 1000 * pow(drive, 2)
        if lidClosed {
            let failed = !driver.applyWithLidClosed(nits: nits)
            if closedLidFailed != failed { closedLidFailed = failed }
            if failed { return }
        } else if !driver.apply(nits: nits, force: force) {
            timer?.invalidate(); timer = nil
            audio.stop()
            _ = driver.restore()
            output = 0
            notice = .init("未能寫入 Logo 亮度。請再揀一次模式。", "Could not set the logo brightness. Select the mode again.")
            return
        }
        if abs(drive - output) > 0.004 || drive == 0 { output = drive }
    }

    private func updateFocus(_ value: Focus?) {
        if focus != value { focus = value }
    }

    func receive(_ event: AgentEvent) {
        let key = event.agent.rawValue + ":" + event.session
        if event.phase == .idle {
            sessions.removeValue(forKey: key)
        } else {
            if sessions.count >= 128, let oldest = sessions.min(by: { $0.value.time < $1.value.time })?.key { sessions.removeValue(forKey: oldest) }
            // Tool heartbeats keep a working session active without restarting the light pulse.
            if event.phase != .working || sessions[key]?.phase != .working {
                sessions[key] = Session(agent: event.agent, phase: event.phase, time: time)
            }
        }
        lastSignal = event
        log.info("Received \(event.agent.rawValue, privacy: .public) \(event.phase.rawValue, privacy: .public)")
        if mode == .agents { tick() }
    }

    func preview(_ agent: Agent) {
        select(.agents)
        guard let url = URL(string: "lidpulse://event/\(agent.rawValue)/working?sid=preview"), let event = AgentEvent(url: url) else { return }
        receive(event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.sessions.removeValue(forKey: agent.rawValue + ":preview")
            self?.tick()
        }
    }

    func refresh() {
        loginStatus = SMAppService.mainApp.status
        ownsBrightnessOverride = BrightnessLimit.hasBackup
        fullRange = driver?.hasFullRange ?? false
        for agent in Agent.allCases { installed[agent] = AgentHooks.connected(agent, at: file(for: agent)) }
    }

    private func file(for agent: Agent) -> URL {
        (folders[agent] ?? agent.folder).appendingPathComponent(agent.filename).resolvingSymlinksInPath()
    }

    func chooseFolder(_ agent: Agent) {
        let picker = NSOpenPanel()
        picker.title = language.text("選擇 \(agent.title) 設定資料夾", "Choose the \(agent.title) settings folder")
        let file = agent == .codex ? "config.toml" : "settings.json"
        picker.message = language.text("揀包含 \(file) 嘅資料夾。", "Select the folder that contains \(file).")
        picker.prompt = language.text("選擇", "Choose")
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.showsHiddenFiles = true
        picker.directoryURL = folders[agent] ?? agent.folder
        NSApp.activate()
        if picker.runModal() == .OK, let url = picker.url {
            folders[agent] = url
            defaults.set(url.path, forKey: agent.rawValue + "Folder")
            refresh()
        }
    }

    func configure(_ agent: Agent) {
        notice = nil
        let connect = installed[agent] != true
        do {
            try AgentHooks.configure(agent, at: file(for: agent), connect: connect)
            refresh()
            if connect {
                notice = agent == .codex
                    ? .init("已加入 Codex hooks。請喺 Codex「設定 → Hooks」或 CLI 輸入 /hooks 審閱並信任。",
                            "Codex hooks added. Review and trust them in Codex Settings → Hooks or with /hooks in the CLI.")
                    : .init("已加入 Claude Code hooks；請開一個新 Claude Code session。",
                            "Claude Code hooks added. Start a new Claude Code session.")
            }
        } catch {
            notice = .init("未能更新設定檔；請檢查所選資料夾同 JSON 格式。",
                           "Could not update the config. Check the selected folder and JSON format.")
        }
    }

    func setLogin(_ enabled: Bool) {
        notice = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
            if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            refresh()
            notice = .init("未能更改登入啟動。請先將 LidPulse 放入「應用程式」。", "Could not change login startup. Move LidPulse to Applications first.")
        }
    }

    func changeFullRange() {
        refresh()
        guard canChangeLimit else { return }
        guard !competingApp else {
            notice = .init("請先退出其他燈控程式，再更改亮度限制。", "Quit other logo controls before changing the brightness limit.")
            return
        }
        let unlock = !ownsBrightnessOverride
        let previous = mode
        select(.system)
        guard notice == nil else { return }
        changingLimit = true
        switch BrightnessLimit.setUnlocked(unlock, language: language) {
        case .cancelled:
            changingLimit = false
            select(previous)
        case .failed:
            changingLimit = false
            refresh()
            notice = .init("未能更改最高亮度。請檢查授權後再試。", "Could not change the brightness limit. Check authorization and try again.")
        case .changed:
            Task { @MainActor in
                var replacement: LogoDriver?
                for _ in 0..<6 {
                    try? await Task.sleep(for: .milliseconds(350))
                    replacement = LogoDriver(recovery: recoveryURL)
                    if let replacement, !unlock || replacement.hasFullRange { break }
                }
                if let replacement { driver = replacement }
                refresh()
                changingLimit = false
                if unlock && !fullRange {
                    notice = .init("已寫入設定，但未確認上限已解除。可喺設定還原。", "The settings were written, but the new limit could not be confirmed. You can restore the previous limits in Settings.")
                } else {
                    select(previous)
                }
            }
        }
    }

    func setKeepLogoWhenLidClosed(_ enabled: Bool) {
        let wasSuspended = suspended
        keepLogoWhenLidClosed = enabled
        defaults.set(enabled, forKey: "keepLogoWhenLidClosed")
        if !enabled { driver?.releaseClosedLid() }
        refreshLidState()
        if updateSuspension(wasSuspended: wasSuspended) { tick(force: true) }
    }

    func suspend(_ source: SuspensionSource, _ sleeping: Bool) {
        let wasSuspended = suspended
        switch source {
        case .display: displayAsleep = sleeping
        case .system:
            systemAsleep = sleeping
            if sleeping { driver?.restoreOpeningFade() }
        case .lock: locked = sleeping
        }
        refreshLidState()
        // A display power transition can reset the hardware's current level.
        if updateSuspension(wasSuspended: wasSuspended), wasSuspended || source == .display {
            tick(force: source == .display)
        }
    }

    func displayConfigurationChanged() {
        if keepLogoWhenLidClosed { tick(force: true) }
    }

    func lidConfigurationChanged() {
        lidHandoff?.cancel()
        lidHandoff = nil
        guard keepLogoWhenLidClosed, mode != .system else { return }
        tick()
        guard lidClosed, !suspended, mode != .dark else { return }

        // Check more frequently only while the native close transition can blank the LED.
        lidHandoff = Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now + .milliseconds(60)
            while clock.now < deadline {
                do { try await clock.sleep(for: .milliseconds(2), tolerance: .zero) }
                catch { return }
                guard let self, self.keepLogoWhenLidClosed, self.lidClosed, !self.suspended else { return }
                if self.driver?.needsClosedLidHandoff == true { self.tick() }
            }
        }
    }

    private func refreshLidState() {
        lidClosed = keepLogoWhenLidClosed && driver?.isLidClosed == true
        if !lidClosed, closedLidFailed { closedLidFailed = false }
    }

    private func updateSuspension(wasSuspended: Bool) -> Bool {
        if suspended {
            if !wasSuspended {
                audio.stop()
                _ = driver?.restore()
            }
            return false
        }
        if wasSuspended {
            if !lidClosed { started = time }
            if mode == .music && !startAudio() { return false }
        }
        return true
    }

    func terminate() {
        timer?.invalidate()
        lidHandoff?.cancel()
        audio.stop()
        driver?.releaseClosedLid()
        driver?.restoreOpeningFade()
        if !competingApp { _ = driver?.restore() }
    }
}
