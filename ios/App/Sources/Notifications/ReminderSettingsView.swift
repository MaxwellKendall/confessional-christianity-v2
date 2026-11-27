import DomainKit
import SwiftUI

struct ReminderSettingsView: View {
    @Environment(\.openURL) private var openURL
    private let scheduler = ReminderScheduler.shared

    var body: some View {
        Form {
            if scheduler.authorization == .denied {
                Button("Allow notifications in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if scheduler.authorization == .notDetermined {
                Text("You’ll be asked to allow notifications after you keep your first sermon week.")
            }
            reminder("Weekday sermon", time: \.weekday, defaultTime: ReminderTime(hour: 9))
            reminder("Saturday preparation", time: \.saturday, defaultTime: ReminderTime(hour: 9))
            reminder("Catechism practice", time: \.catechism, defaultTime: ReminderTime(hour: 17))
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { scheduler.refresh() }
    }

    private func reminder(_ title: String, time key: WritableKeyPath<ReminderSettings, ReminderTime?>,
                          defaultTime: ReminderTime) -> some View {
        let available = scheduler.isReady && scheduler.authorization != .denied
        let time = scheduler.settings[keyPath: key]
        return Section {
            Toggle(title, isOn: Binding(
                get: { available && scheduler.settings[keyPath: key] != nil },
                set: { set($0 ? defaultTime : nil, for: key) }
            ))
            .disabled(!available)
            if available, let time {
                DatePicker("Time", selection: Binding(
                    get: {
                        let calendar = Calendar.current
                        return calendar.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
                    },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        if let hour = parts.hour, let minute = parts.minute {
                            set(ReminderTime(hour: hour, minute: minute), for: key)
                        }
                    }
                ), displayedComponents: .hourAndMinute)
            }
        }
    }

    private func set(_ time: ReminderTime?, for key: WritableKeyPath<ReminderSettings, ReminderTime?>) {
        var settings = scheduler.settings
        settings[keyPath: key] = time
        scheduler.update(settings)
    }
}
