//
//  EditableEffectNameHeader.swift
//  Hypnograph
//

import SwiftUI

struct EditableEffectNameHeader: View {
    let name: String
    let onSave: (String) -> Void
    var focusedField: FocusState<EffectsEditorField?>.Binding

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack {
            if isEditing {
                TextField("Effect Name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(6)
                    .focused(focusedField, equals: .effectName)
                    .onSubmit {
                        saveAndClose()
                    }
                    .onAppear {
                        // Auto-focus the text field when editing starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField.wrappedValue = .effectName
                        }
                    }

                Button(action: saveAndClose) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button(action: {
                    isEditing = false
                    focusedField.wrappedValue = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                Text(name)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                editedName = name
                isEditing = true
            }
        }
        .onChange(of: name) { _, _ in
            if isEditing {
                isEditing = false
                focusedField.wrappedValue = nil
            }
        }
    }

    private func saveAndClose() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSave(trimmed)
        }
        isEditing = false
        focusedField.wrappedValue = nil
    }
}

