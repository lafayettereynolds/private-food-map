import SwiftUI

struct VisitContextChoiceOption: Identifiable, Equatable {
    let value: String
    let title: String
    var id: String { value }
}

struct VisitOptionalChoicePicker: View {
    let title: String
    @Binding var selection: String?
    let options: [VisitContextChoiceOption]
    let accessibilityIdentifier: String

    var body: some View {
        Menu {
            Button("不记录") { selection = nil }
                .accessibilityLabel("\(title)：不记录")
            ForEach(options) { option in
                Button(option.title) { selection = option.value }
            }
        } label: {
            LabeledContent(title) {
                Text(selectedTitle)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var selectedTitle: String {
        guard let selection else { return "不记录" }
        return options.first(where: { $0.value == selection })?.title ?? selection
    }
}

struct VisitMultiChoicePicker: View {
    let title: String
    @Binding var selection: [String]
    let options: [VisitContextChoiceOption]
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                if !knownSelection.isEmpty {
                    Button("清空") { removeKnownValues() }
                        .font(.caption)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let selected = selection.contains(option.value)
                        Button {
                            toggle(option.value)
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09),
                                    in: Capsule()
                                )
                                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selected ? "已选择" : "未选择")
                        .accessibilityIdentifier("\(accessibilityIdentifier)-\(option.value)")
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var knownSelection: [String] {
        selection.filter { value in options.contains { $0.value == value } }
    }

    private func toggle(_ value: String) {
        if selection.contains(value) {
            selection.removeAll { $0 == value }
        } else {
            selection.append(value)
        }
        selection = VisitStringArrayStorage.normalized(selection)
    }

    private func removeKnownValues() {
        let known = Set(options.map(\.value))
        selection.removeAll { known.contains($0) }
    }
}

struct VisitTagPicker: View {
    let title: String
    @Binding var selection: [String]
    let presets: [String]
    let accessibilityIdentifier: String

    @State private var customValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                if !selection.isEmpty {
                    Button("清空") { selection = [] }
                        .font(.caption)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(allOptions, id: \.self) { option in
                        let selected = selection.contains(option)
                        Button {
                            if selected { selection.removeAll { $0 == option } }
                            else { selection.append(option) }
                            selection = VisitStringArrayStorage.normalized(selection)
                        } label: {
                            Text(option)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09),
                                    in: Capsule()
                                )
                                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            HStack {
                TextField("添加自定义标签", text: $customValue)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addCustomValue)
                Button("添加", action: addCustomValue)
                    .disabled(customValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var allOptions: [String] {
        presets + selection.filter { !presets.contains($0) }
    }

    private func addCustomValue() {
        let value = customValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        selection = VisitStringArrayStorage.normalized(selection + [String(value.prefix(12))])
        customValue = ""
    }
}
