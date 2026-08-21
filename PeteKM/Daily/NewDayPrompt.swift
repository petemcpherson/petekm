import SwiftUI

/// The tiny keyboard-first New Day prompt (§7.3). Arrow keys move, Enter picks, Esc picks scratch.
struct NewDayPrompt: View {
    let options: [NewDayStart]
    let onChoose: (NewDayStart) -> Void

    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("New day.")
                .font(DS.Text.title3)
                .foregroundStyle(DS.Color.textPrimary)

            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    row(option, index: index)
                }
            }
        }
        .padding(DS.Space.s6)
        .frame(width: 280, alignment: .leading)
        .background(DS.Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.borderHairline)
        )
        .shadow(radius: 18, y: 6)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { choose(selection); return .handled }
        .onKeyPress(.escape) { onChoose(.scratch); return .handled }
    }

    private func row(_ option: NewDayStart, index: Int) -> some View {
        Button {
            choose(index)
        } label: {
            HStack {
                Text(option.title)
                    .font(DS.Text.body)
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(DS.Text.monoCaption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.vertical, DS.Space.s3)
            .padding(.horizontal, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(index == selection ? DS.Color.accentTint : Color.clear)
            .foregroundStyle(index == selection ? DS.Color.accent : DS.Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
    }

    private func move(_ delta: Int) {
        guard !options.isEmpty else { return }
        selection = (selection + delta + options.count) % options.count
    }

    private func choose(_ index: Int) {
        guard options.indices.contains(index) else { return }
        onChoose(options[index])
    }
}
