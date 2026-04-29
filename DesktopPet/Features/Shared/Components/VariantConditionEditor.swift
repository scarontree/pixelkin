import SwiftUI

/// 动画变体条件标签编辑器 — 支持时间/点击/应用分组预设 + 自由输入
struct VariantConditionEditor: View {
    let stateKey: String
    @Binding var conditions: [String]
    /// 当前规则集（用于动态获取应用分组预设）
    var ruleSet: BubbleRuleSet = .builtInDefault
    @State private var newConditionInput: String = ""
    
    private let timePresets: [(String, String)] = [
        ("morning", "早晨"),
        ("afternoon", "下午"),
        ("evening", "傍晚"),
        ("night", "深夜")
    ]
    
    private let clickPresets: [(String, String)] = [
        ("click_1", "连击1次"),
        ("click_2", "连击2次"),
        ("click_3", "连击3次"),
        ("multi_click", "3次以上连击")
    ]
    
    /// 从当前 ruleSet 动态获取应用分组（用户新增的分组会自动出现）
    private var appGroupPresets: [(String, String)] {
        ruleSet.appGroupPresets.map { ($0.key, $0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("触发条件")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            if !conditions.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(conditions, id: \.self) { condition in
                        HStack(spacing: 4) {
                            Text(condition)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                conditions.removeAll { $0 == condition }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                    }
                }
            }
            
            HStack {
                TextField("输入应用名 (如 Safari) 或其他条件", text: $newConditionInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addCondition(newConditionInput)
                    }
                Button("添加") {
                    addCondition(newConditionInput)
                }
                .buttonStyle(.bordered)
                .disabled(newConditionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                presetRow(title: "时间预设:", presets: timePresets)
                
                if stateKey == "click" {
                    presetRow(title: "点击预设:", presets: clickPresets)
                }
                
                presetRow(title: "应用预设:", presets: appGroupPresets)
            }
        }
    }
    
    @ViewBuilder
    private func presetRow(title: String, presets: [(String, String)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                ForEach(presets, id: \.0) { preset in
                    Button {
                        addCondition(preset.0)
                    } label: {
                        Text(preset.1)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(conditions.contains(preset.0))
                }
            }
        }
    }

    private func addCondition(_ condition: String) {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !conditions.contains(trimmed) {
            conditions.append(trimmed)
        }
        newConditionInput = ""
    }
}
