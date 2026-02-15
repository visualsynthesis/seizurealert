import SwiftUI
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "PhoneContentView")

struct PhoneContentView: View {
    @ObservedObject private var connectivityManager = PhoneConnectivityManager.shared
    @State private var contactName: String = ""
    @State private var phoneNumber: String = ""
    @State private var showSaveSuccess = false
    @State private var showingClearHistory = false

    var body: some View {
        NavigationView {
            List {
                // App header
                Section(header: Text("SeizureGuard")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Companion App")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("iPhone + Watch Alert System")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        Circle()
                            .fill(connectivityManager.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                            .accessibilityLabel(connectivityManager.isConnected ? "Connected" : "Disconnected")
                    }
                    .padding(.vertical, 4)
                }

                // Connection status
                Section(header: Text("Connection Status")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Watch Connection", systemImage: "applewatch")
                            Spacer()
                            Text(connectivityManager.isConnected ? "Connected" : "Disconnected")
                                .fontWeight(.semibold)
                                .foregroundColor(connectivityManager.isConnected ? .green : .red)
                        }

                        if connectivityManager.isWatchPaired() {
                            Text("Watch is paired and ready")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No watch paired. Please pair in Settings.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Emergency contact config
                Section(
                    header: Text("Emergency Contact"),
                    footer: Text("This contact receives the alert when a seizure is detected.")
                ) {
                    TextField("Contact Name", text: $contactName)
                        .textContentType(.name)
                        .accessibilityLabel("Emergency contact name")

                    TextField("Phone Number", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .accessibilityLabel("Emergency contact phone number")
                        .accessibilityHint("Enter at least 10 digits")

                    Button("Save Contact") {
                        saveContact()
                    }
                    .disabled(phoneNumber.filter { $0.isNumber }.count < 10)
                    .accessibilityLabel("Save emergency contact")

                    if showSaveSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Contact saved")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("Contact saved successfully")
                    }
                }

                // Test alert
                Section(header: Text("Testing")) {
                    Button(action: sendTestAlert) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                            Text("Send Test Alert")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundColor(.blue)
                    .accessibilityLabel("Send test alert")
                    .accessibilityHint("Sends a test seizure alert to verify notifications and SMS work")
                }

                // Alert history
                if !connectivityManager.alertHistory.isEmpty {
                    Section(header: HStack {
                        Text("Recent Alerts")
                        Spacer()
                        Button("Clear") { showingClearHistory = true }
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityLabel("Clear alert history")
                    }) {
                        ForEach(connectivityManager.alertHistory.prefix(10), id: \.timestamp) { alert in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Seizure Alert")
                                    .fontWeight(.semibold)

                                Text(DateFormatter.localizedString(
                                    from: alert.timestamp,
                                    dateStyle: .short,
                                    timeStyle: .medium
                                ))
                                .font(.caption)
                                .foregroundColor(.secondary)

                                if let url = URL(string: alert.mapsLink) {
                                    Link(destination: url) {
                                        HStack {
                                            Image(systemName: "mappin.circle.fill")
                                            Text("View Location")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.blue)
                                    }
                                    .accessibilityLabel("View alert location on map")
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                } else {
                    Section(header: Text("Recent Alerts")) {
                        Text("No alerts yet")
                            .foregroundColor(.secondary)
                    }
                }

                // Setup instructions
                Section(header: Text("Setup Guide")) {
                    VStack(alignment: .leading, spacing: 12) {
                        instructionRow(number: "1", title: "Install Watch App",
                                       detail: "Install SeizureGuard on your paired Apple Watch")
                        instructionRow(number: "2", title: "Set Emergency Contact",
                                       detail: "Enter the phone number above and tap Save")
                        instructionRow(number: "3", title: "Grant Permissions",
                                       detail: "Allow Location, Motion, and Notification access")
                        instructionRow(number: "4", title: "Test It",
                                       detail: "Use Send Test Alert to verify delivery")
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("SeizureGuard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadContact()
        }
        .alert("Clear Alert History?", isPresented: $showingClearHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                connectivityManager.clearAlertHistory()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private func instructionRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number + ".")
                .fontWeight(.bold)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadContact() {
        if let contact = EmergencyContact.load() {
            contactName = contact.name
            phoneNumber = contact.phoneNumber
        }
    }

    private func saveContact() {
        let contact = EmergencyContact(
            name: contactName.isEmpty ? "Emergency Contact" : contactName,
            phoneNumber: phoneNumber.filter { $0.isNumber }
        )
        contact.save()
        logger.info("Contact saved: \(contact.displayName)")

        showSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showSaveSuccess = false
        }
    }

    private func sendTestAlert() {
        let contact = EmergencyContact.load() ?? EmergencyContact(name: contactName, phoneNumber: phoneNumber)

        let testAlert = AlertMessage(
            timestamp: Date(),
            latitude: 37.7749,   // Placeholder for test
            longitude: -122.4194,
            contactName: contact.name,
            contactPhone: contact.phoneNumber,
            wearerName: EmergencyContact.loadWearerName()
        )

        AlertService.shared.sendAlert(testAlert)
        logger.info("Test alert dispatched")
    }
}

#Preview {
    PhoneContentView()
}
