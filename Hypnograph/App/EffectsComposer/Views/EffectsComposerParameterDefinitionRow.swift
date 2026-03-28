//
//  EffectsComposerParameterDefinitionRow.swift
//  Hypnograph
//

import SwiftUI

struct EffectsComposerParameterDefinitionRow: View {
    @Binding var parameter: EffectsComposerParameterDraft
    let onChanged: () -> Void
    let onInsert: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("name", text: Binding(
                    get: { parameter.name },
                    set: { parameter.name = $0; onChanged() }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 130, maxWidth: .infinity)

                Picker("Type", selection: Binding(
                    get: { parameter.type },
                    set: {
                        parameter.type = $0
                        if parameter.type == .choice {
                            if parameter.choiceOptions.isEmpty {
                                parameter.choiceOptions = [
                                    EffectsComposerChoiceOption(key: "option1", label: "Option 1")
                                ]
                            }
                            if !parameter.choiceOptions.contains(where: { $0.key == parameter.defaultChoiceKey }) {
                                parameter.defaultChoiceKey = parameter.choiceOptions.first?.key ?? ""
                            }
                        }
                        onChanged()
                    }
                )) {
                    ForEach(EffectsComposerParamType.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            HStack(spacing: 8) {
                Picker("Binding", selection: Binding(
                    get: { parameter.autoBind },
                    set: {
                        parameter.autoBind = $0
                        onChanged()
                    }
                )) {
                    ForEach(EffectsComposerAutoBind.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Spacer(minLength: 0)

                Button {
                    onInsert(parameter.name)
                } label: {
                    Label("Insert Usage", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
            }

            if parameter.type == .bool {
                Toggle("Default", isOn: Binding(
                    get: { parameter.defaultBool },
                    set: { parameter.defaultBool = $0; onChanged() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            } else if parameter.type == .choice {
                choiceEditor
            } else {
                HStack(spacing: 10) {
                    numberField(
                        title: "Default",
                        value: Binding(
                            get: { parameter.defaultNumber },
                            set: { parameter.defaultNumber = $0; onChanged() }
                        )
                    )

                    numberField(
                        title: "Min",
                        value: Binding(
                            get: { parameter.minNumber },
                            set: { parameter.minNumber = $0; onChanged() }
                        )
                    )

                    numberField(
                        title: "Max",
                        value: Binding(
                            get: { parameter.maxNumber },
                            set: { parameter.maxNumber = $0; onChanged() }
                        )
                    )
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func numberField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var choiceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Options")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let newKey = nextChoiceKey()
                    parameter.choiceOptions.append(
                        EffectsComposerChoiceOption(
                            key: newKey,
                            label: "Option \(parameter.choiceOptions.count + 1)"
                        )
                    )
                    if parameter.defaultChoiceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parameter.defaultChoiceKey = newKey
                    }
                    onChanged()
                } label: {
                    Label("Add Option", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach($parameter.choiceOptions) { $option in
                HStack(spacing: 8) {
                    TextField("key", text: Binding(
                        get: { option.key },
                        set: {
                            let previousKey = option.key
                            option.key = $0
                            if parameter.defaultChoiceKey == previousKey {
                                parameter.defaultChoiceKey = $0
                            }
                            onChanged()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)

                    TextField("label", text: Binding(
                        get: { option.label },
                        set: {
                            option.label = $0
                            onChanged()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        let removedKey = option.key
                        parameter.choiceOptions.removeAll { $0.id == option.id }
                        if parameter.defaultChoiceKey == removedKey {
                            parameter.defaultChoiceKey = parameter.choiceOptions.first?.key ?? ""
                        }
                        onChanged()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }

            if !parameter.choiceOptions.isEmpty {
                Picker("Default", selection: Binding(
                    get: { parameter.defaultChoiceKey },
                    set: {
                        parameter.defaultChoiceKey = $0
                        onChanged()
                    }
                )) {
                    ForEach(parameter.choiceOptions) { option in
                        Text(option.label.isEmpty ? option.key : option.label)
                            .tag(option.key)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .font(.caption)
    }

    private func nextChoiceKey() -> String {
        let existing = Set(parameter.choiceOptions.map { $0.key })
        var index = 1
        while existing.contains("option\(index)") {
            index += 1
        }
        return "option\(index)"
    }
}
