import ServiceManagement
import SwiftUI

struct LidSettings: View {
    @Bindable var model: LidModel
    private var lang: Language { model.language }

    var body: some View {
        Form {
            Section(lang.text("一般", "General")) {
                Picker(lang.text("介面語言", "Language"), selection: $model.language) {
                    ForEach(Language.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                Toggle(lang.text("登入時開啟", "Open at Login"), isOn: Binding(
                    get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                    set: { model.setLogin($0) }
                ))
                if model.loginStatus == .requiresApproval {
                    Button(lang.text("到系統設定允許登入啟動", "Allow Login Startup in System Settings")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
            Section(lang.text("Logo 亮度", "Logo Brightness")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(lang.text("最高亮度", "Full Brightness"))
                        Spacer()
                        if model.changingLimit { ProgressView().controlSize(.small) }
                        if model.ownsBrightnessOverride {
                            Button(lang.text("還原原本限制…", "Restore Previous Limits…")) { model.changeFullRange() }
                                .disabled(!model.canChangeLimit)
                        } else if model.fullRange {
                            Text(lang.text("已解除限制", "Already Unlocked")).foregroundStyle(.secondary)
                        } else {
                            Button(lang.text("解除亮度限制…", "Unlock Full Brightness…")) { model.changeFullRange() }
                                .disabled(!model.canChangeLimit)
                        }
                    }
                    Text(lang.text("容許 Logo 喺昏暗環境用到最高亮度。更改或還原時，macOS 會要求管理員授權。",
                                   "Lets the logo reach full brightness in dim rooms. macOS asks for administrator approval to change or restore the limit."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(lang.text("AI 連接", "Agent Connections")) {
                ForEach(Agent.allCases) { agent in
                    agentRow(agent)
                }
                if let event = model.lastEvent {
                    Text(lang.text("最近事件：\(event)", "Last event: \(event)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = model.message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 465, height: 505)
        .environment(\.locale, lang.locale)
        .onAppear { model.refresh() }
    }

    private func agentRow(_ agent: Agent) -> some View {
        let connected = model.installed[agent] == true
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.title).font(.body.weight(.medium))
                Text(connected ? lang.text("已加入 hooks", "Hooks added") : lang.text("未連接", "Not connected"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(lang.text("試燈", "Test Light")) { model.preview(agent) }
                .accessibilityLabel(lang.text("試 \(agent.title) 狀態燈", "Test the \(agent.title) light"))
            Button(connected ? lang.text("移除", "Remove") : lang.text("連接", "Connect")) { model.configure(agent) }
                .accessibilityLabel(connected
                    ? lang.text("移除 \(agent.title) hooks", "Remove \(agent.title) hooks")
                    : lang.text("連接 \(agent.title)", "Connect \(agent.title)"))
            Button { model.chooseFolder(agent) } label: { Image(systemName: "folder") }
                .help(model.folders[agent]?.path ?? lang.text("揀設定資料夾", "Choose the settings folder"))
                .accessibilityLabel(lang.text("揀 \(agent.title) 設定資料夾", "Choose the \(agent.title) settings folder"))
        }
        .controlSize(.small)
    }
}
