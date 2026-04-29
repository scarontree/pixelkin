import SwiftUI

/// 角色管理视图
struct PersonasView: View {
    let coordinator: AppCoordinator

    @State private var personas: [Persona] = []
    @State private var selectedID: String? = nil
    @State private var editingPersona: Persona? = nil

    var body: some View {
        VStack(spacing: 0) {
            if personas.isEmpty {
                emptyState
            } else {
                personaList
            }
        }
        .navigationTitle("角色")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addPersona) {
                    Label("新建角色", systemImage: "plus")
                }
            }
        }
        .onAppear {
            personas = PersonaService.loadAll()
        }
        .sheet(item: $editingPersona) { editing in
            PersonaEditorModal(
                persona: editing,
                isNew: !personas.contains(where: { $0.id == editing.id }),
                onSave: { saved in
                    savePersona(saved)
                    editingPersona = nil
                },
                onCancel: {
                    editingPersona = nil
                }
            )
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("还没有角色")
                .font(.title3.weight(.semibold))
            Text("创建一个角色来定义宠物的性格和说话方式")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("创建角色") { addPersona() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 角色列表

    private var personaList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(personas) { persona in
                    PersonaCard(
                        persona: persona,
                        isSelected: persona.id == selectedID,
                        onEdit: {
                            editingPersona = persona
                        },
                        onDelete: {
                            deletePersona(persona)
                        }
                    )
                    .onTapGesture {
                        selectedID = persona.id
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - 操作

    private func addPersona() {
        let newPersona = Persona(
            id: UUID().uuidString,
            name: "新角色",
            systemPrompt: "",
            greeting: "",
            skinID: ""
        )
        editingPersona = newPersona
    }

    private func savePersona(_ persona: Persona) {
        if let index = personas.firstIndex(where: { $0.id == persona.id }) {
            personas[index] = persona
        } else {
            personas.append(persona)
        }
        PersonaService.saveAll(personas)
    }

    private func deletePersona(_ persona: Persona) {
        personas.removeAll { $0.id == persona.id }
        PersonaService.saveAll(personas)
        if selectedID == persona.id {
            selectedID = personas.first?.id
        }
    }
}

// MARK: - 角色卡片

private struct PersonaCard: View {
    let persona: Persona
    let isSelected: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.5), .pink.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(persona.name.prefix(1)))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(persona.name)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                    if !persona.greeting.isEmpty {
                        Text(persona.greeting)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Menu {
                    Button("编辑", action: onEdit)
                    Divider()
                    Button("删除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if !persona.systemPrompt.isEmpty {
                Text(persona.systemPrompt)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - 角色编辑弹窗

private struct PersonaEditorModal: View {
    @State var persona: Persona
    let isNew: Bool
    let onSave: (Persona) -> Void
    let onCancel: () -> Void

    @State private var availableSkins: [SkinManifest] = []

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text(isNew ? "新建角色" : "编辑角色")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                editorField("角色名称", text: $persona.name)

                VStack(alignment: .leading, spacing: 6) {
                    Text("人设提示词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $persona.systemPrompt)
                        .font(.body)
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                editorField("开场白", text: $persona.greeting)

                VStack(alignment: .leading, spacing: 6) {
                    Text("关联皮肤 ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $persona.skinID) {
                        Text("可选").tag("")
                        ForEach(availableSkins) { skin in
                            Text(skin.name).tag(skin.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            Spacer(minLength: 16)

            // 按钮
            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    onSave(persona)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(persona.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .frame(minHeight: 400)
        .onAppear {
            availableSkins = SkinService.discoverAllSkinsFlat()
        }
    }

    private func editorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
