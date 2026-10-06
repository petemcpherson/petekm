import SwiftUI

/// The sync light at the trailing end of the sticky header. Always shown while
/// automatic sync is on: green when everything is on GitHub, yellow while changes
/// wait to go out, grey offline, red when something needs the user. It pulses
/// during a run. Hover shows the status; click opens Sync Now and Details.
struct SyncStatusDot: View {

    @Environment(AutoSync.self) private var autoSync

    let onSyncNow: () -> Void

    @State private var isPresented = false
    @State private var showsCard = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isDimmed = false
    @State private var pulseStartedAt: Date?

    /// A run often takes well under a second; keep the pulse long enough to see.
    private static let minimumPulse: TimeInterval = 1.2
    private static let hoverDelay: Duration = .milliseconds(300)

    var body: some View {
        let style = autoSync.dotStyle
        if style != .hidden {
            Button {
                hideCard()
                isPresented.toggle()
            } label: {
                Circle()
                    .fill(Self.color(style))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
                    .frame(width: 8, height: 8)
                    .opacity(isDimmed ? 0.3 : 1)
                    .padding(DS.Space.s2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(autoSync.statusLine ?? "Sync status")
            .onHover { hovering in
                hoverTask?.cancel()
                guard hovering else {
                    hideCard()
                    return
                }
                hoverTask = Task {
                    try? await Task.sleep(for: Self.hoverDelay)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) { showsCard = true }
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsCard, !isPresented {
                    SyncStatusLines()
                        .padding(DS.Space.s4)
                        .frame(width: 280, alignment: .leading)
                        .background(DS.Color.surfaceCard, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Color.borderHairline))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(y: 24)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                SyncStatusPopover(onSyncNow: {
                    isPresented = false
                    onSyncNow()
                })
            }
            .task(id: autoSync.isSyncing) { await pulse(autoSync.isSyncing) }
        }
    }

    private func hideCard() {
        hoverTask?.cancel()
        hoverTask = nil
        showsCard = false
    }

    private func pulse(_ syncing: Bool) async {
        if syncing {
            pulseStartedAt = Date()
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        } else if let started = pulseStartedAt {
            let left = Self.minimumPulse - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled else { return }
            pulseStartedAt = nil
            withAnimation(.easeInOut(duration: 0.3)) { isDimmed = false }
        }
    }

    static func color(_ style: SyncDotStyle) -> Color {
        switch style {
        case .hidden, .neutral, .offline: DS.Color.grey400
        case .synced: DS.Color.success
        case .pending: Color(nsColor: .systemYellow)
        case .problem: DS.Color.error
        }
    }
}

/// Status, last check for updates, and last change from another Mac. Shared by
/// the hover card and the popover.
private struct SyncStatusLines: View {

    @Environment(AutoSync.self) private var autoSync

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let line = autoSync.statusLine {
                Text(line)
                    .font(DS.Text.callout)
                    .foregroundStyle(autoSync.dotStyle == .problem ? DS.Color.error : DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fetched = autoSync.fetchLine {
                Text(fetched)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            if let other = autoSync.otherDeviceLine {
                Text(other)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
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
            SyncStatusLines()
            HStack {
                Button("Sync Now", action: onSyncNow)
                Spacer(minLength: DS.Space.s6)
                Button(showsDetails ? "Hide Details" : "Details…") {
                    showsDetails.toggle()
                }
                .buttonStyle(.link)
            }
            if showsDetails {
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
