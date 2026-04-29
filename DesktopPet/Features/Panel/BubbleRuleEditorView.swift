import SwiftUI

/// 气泡规则编辑器 — 应用分组 / 时间段 / 特殊日期规则的编辑视图
/// 从 SkinFilesEditorModal 中拆出，接收 Binding<BubbleRuleSet>
struct BubbleRuleEditorView: View {
    let key: String
    @Binding var ruleSet: BubbleRuleSet
    
    @State private var newAppInput: String = ""
    
    var body: some View {
        if key == "default" {
            EmptyView()
        } else if let index = ruleSet.timeRules?.firstIndex(where: { $0.id == key }) {
            timeRuleEditor(index: index)
        } else if let index = ruleSet.dateRules?.firstIndex(where: { $0.id == key }) {
            dateRuleEditor(index: index)
        } else {
            appRuleEditor(key: key)
        }
    }
    
    // MARK: - 应用规则编辑器
    
    @ViewBuilder
    private func appRuleEditor(key: String) -> some View {
        let groupName: String = {
            if let rule = ruleSet.rules.first(where: { $0.id == key }) {
                return rule.appGroup ?? key
            }
            return key
        }()
        
        let apps = ruleSet.appGroups[groupName] ?? []
        
        VStack(alignment: .leading, spacing: 14) {
            Text("触发规则配置")
                .font(.headline)
            
            Text("当打开以下任一应用时触发此场景：")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(apps, id: \.self) { app in
                    HStack(spacing: 4) {
                        Text(app)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            var current = ruleSet.appGroups[groupName] ?? []
                            current.removeAll { $0 == app }
                            ruleSet.appGroups[groupName] = current
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                }
            }
            
            HStack {
                TextField("输入应用名或包名 (如 Bilibili 或 com.apple.Safari)", text: $newAppInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addApp(groupName: groupName, key: key)
                    }
                Button("添加") {
                    addApp(groupName: groupName, key: key)
                }
                .buttonStyle(.bordered)
                .disabled(newAppInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func addApp(groupName: String, key: String) {
        let trimmed = newAppInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var apps = ruleSet.appGroups[groupName] ?? []
        if !apps.contains(trimmed) {
            apps.append(trimmed)
            ruleSet.appGroups[groupName] = apps
        }
        newAppInput = ""
        
        if !ruleSet.rules.contains(where: { $0.id == key }) {
            let newRule = BubbleRule(id: key, appGroup: groupName, probability: 0.3, cooldown: 45)
            ruleSet.rules.append(newRule)
        } else if let idx = ruleSet.rules.firstIndex(where: { $0.id == key }) {
            ruleSet.rules[idx].appGroup = groupName
        }
    }
    
    // MARK: - 时间规则编辑器
    
    @ViewBuilder
    private func timeRuleEditor(index: Int) -> some View {
        let startBinding = Binding<Int>(
            get: { ruleSet.timeRules?[index].startHour ?? 0 },
            set: { ruleSet.timeRules?[index].startHour = $0 }
        )
        let endBinding = Binding<Int>(
            get: { ruleSet.timeRules?[index].endHour ?? 0 },
            set: { ruleSet.timeRules?[index].endHour = $0 }
        )
        
        VStack(alignment: .leading, spacing: 14) {
            Text("触发规则配置")
                .font(.headline)
            
            HStack(spacing: 16) {
                labeledNumberField("开始小时 (0-23)", value: startBinding)
                labeledNumberField("结束小时 (0-23)", value: endBinding)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 日期规则编辑器
    
    @ViewBuilder
    private func dateRuleEditor(index: Int) -> some View {
        let rule = ruleSet.dateRules![index]
        VStack(alignment: .leading, spacing: 14) {
            Text("触发规则配置")
                .font(.headline)
            
            if rule.month != nil || rule.day != nil {
                HStack(spacing: 16) {
                    let monthBinding = Binding<Int>(
                        get: { ruleSet.dateRules?[index].month ?? 1 },
                        set: { ruleSet.dateRules?[index].month = $0 }
                    )
                    let dayBinding = Binding<Int>(
                        get: { ruleSet.dateRules?[index].day ?? 1 },
                        set: { ruleSet.dateRules?[index].day = $0 }
                    )
                    labeledNumberField("月份", value: monthBinding)
                    labeledNumberField("日期", value: dayBinding)
                }
            } else if rule.weekdays != nil {
                Text("选择触发的星期：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                let days = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        let isSelected = (ruleSet.dateRules?[index].weekdays ?? []).contains(day)
                        Button {
                            var current = ruleSet.dateRules?[index].weekdays ?? []
                            if isSelected {
                                current.removeAll { $0 == day }
                            } else {
                                current.append(day)
                                current.sort()
                            }
                            ruleSet.dateRules?[index].weekdays = current.isEmpty ? nil : current
                        } label: {
                            Text(days[day - 1])
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 内部辅助
    
    private func labeledNumberField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
    }
}
