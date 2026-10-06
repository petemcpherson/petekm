import SwiftUI

/// The window's one sync signal (sync v2 §8.2): a 6pt dot in the top-trailing
/// corner, shown only when something needs the user. Click for the status popover.
struct SyncStatusDot: View {

    @Environment(AutoSync.self) private var autoSync

    let onSyncNow: () -> Void

    @State private var isPresented = false

    var body: some View {
        let style = autoSync.dotStyle
        if style != .hidden {
            Button {
                isPresented.toggle()
            } label: {
                Circle()
                    .fill(style == .orange ? Color.orange : DS.Color.textSecondary)
                    .frame(width: 6, height: 6)
                    .padding(DS.Space.s2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(autoSync.statusLine ?? "")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                SyncStatusPopover(onSyncNow: {
                    isPresented = false
                    onSyncNow()
                })
            }
        }
    }
}

private struct SyncStatusPopover: View {

    @Environment(AutoSync.self) private var autoSync

    let onSyncNow: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if let line = autoSync.statusLine {
                Text(line)
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let other = autoSync.otherDeviceLine {
                Text(other)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            HStack {
                Button("Sync Now", action: onSyncNow)
                Spacer(minLength: DS.Space.s6)
                Button(showsDetails ? "Hide Details" : "Details…") {
                    showsDetails.toggle()
                }
                .buttonStyle(.link)
            }
            if showsDetails {
                // The only place git output ever appears (§8.2).
                ScrollView {
                    Text(details)
                        .font(DS.Text.mono)
                        .foregroundStyle(DS.Color.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.s3)
                }
                .frame(height: 120)
                .background(DS.Color.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(DS.Space.s6)
        .frame(width: 320)
    }

    private var details: String {
        let stderr = autoSync.lastRunStderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? "Nothing to show." : stderr
    }
}
