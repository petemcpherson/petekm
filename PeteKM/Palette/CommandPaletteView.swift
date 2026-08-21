//
//  CommandPaletteView.swift
//  PeteKM
//
//  The ⌘K panel (DESIGN §12): floating card over a scrim, keyboard-first,
//  visually compact, easy to dismiss.
//

import SwiftUI

struct CommandPaletteView: View {
    @Bindable var model: PaletteModel

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { model.dismiss() }

            panel
                .padding(.top, DS.Space.s9)
                .padding(.horizontal, DS.Space.s6)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var panel: some View {
        VStack(spacing: 0) {
            field
            if model.message != nil || !model.rows.isEmpty {
                Divider()
                results
            }
        }
        .frame(maxWidth: 560)
        .background(DS.Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.borderHairline)
        )
        .shadow(radius: 24, y: 8)
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: DS.Space.s4) {
            if let breadcrumb = model.mode.breadcrumb {
                Text(breadcrumb)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.accent)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s1)
                    .background(DS.Color.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
            } else {
                PixelMark(size: 14)
            }

            TextField(model.mode.prompt, text: $model.query)
                .textFieldStyle(.plain)
                .font(DS.Text.title3)
                .foregroundStyle(DS.Color.textPrimary)
                .focused($focused)
                .onSubmit { model.commit() }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.escape) { model.back(); return .handled }
                .onKeyPress(.delete) {
                    guard model.query.isEmpty, model.mode != .commands else { return .ignored }
                    model.back()
                    return .handled
                }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s5)
    }

    @ViewBuilder
    private var results: some View {
        if let message = model.message {
            Text(message)
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s6)
                .padding(.vertical, DS.Space.s5)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                            PaletteRowView(row: row, isSelected: index == model.selection)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.select(index)
                                    model.commit(row)
                                }
                        }
                    }
                    .padding(.vertical, DS.Space.s2)
                }
                .frame(maxHeight: 360)
                .onChange(of: model.selection) { _, new in
                    guard model.rows.indices.contains(new) else { return }
                    withAnimation(.linear(duration: DS.Duration.instant)) {
                        proxy.scrollTo(model.rows[new].id, anchor: .center)
                    }
                }
            }
        }
    }
}

/// Selected row is a solid accent fill with white text (DESIGN §12).
private struct PaletteRowView: View {
    let row: PaletteRow
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s4) {
                Text(row.title)
                    .font(DS.Text.body)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s4)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(DS.Text.monoCaption)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : DS.Color.textTertiary)
                }
            }
            if let snippet = row.snippet {
                Text(snippet)
                    .font(DS.Text.caption)
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : DS.Color.textSecondary)
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? Color.white : DS.Color.textPrimary)
        .background(isSelected ? DS.Color.accent : Color.clear)
    }
}
