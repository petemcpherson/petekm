import AppKit
import SwiftUI

/// Records a global shortcut by capturing the next key press (§8.2, §18.2).
struct ShortcutRecorder: View {

    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s4) {
                Button(buttonTitle) {
                    if isRecording { stopRecording() } else { startRecording() }
                }
                .frame(minWidth: 150)

                if combo != nil && !isRecording {
                    Button("Clear") {
                        combo = nil
                        rejected = nil
                    }
                    .buttonStyle(.link)
                }
            }

            if let rejected {
                Text(rejected)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.error)
            } else if let warning = combo?.systemConflictWarning {
                Text("\(warning) PeteKM may never see it.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.warning)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var buttonTitle: String {
        if isRecording { return "Press keys…" }
        return combo?.displayString ?? "Record Shortcut"
    }

    private func startRecording() {
        rejected = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil                       // swallow the key so it never reaches the editor
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            stopRecording()                  // bare Esc cancels
            return
        }
        guard let recorded = KeyCombo.from(event: event) else {
            rejected = "Add ⌃, ⌥, or ⌘ — a plain key would fire while you type."
            return
        }
        combo = recorded
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
