import SwiftUI
import WatchKit
import CoreLocation
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "SettingsView")

struct SettingsView: View {
    @State private var wearerName: String = ""
    @State private var contactName: String = ""
    @State private var phoneNumber: String = ""
    @State private var showValidationError = false
    @State private var showSaveSuccess = false
    @State private var showTestAlertSent = false
    @State private var showTestAlertFailed = false
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.dismiss) var dismiss

    var isPhoneNumberValid: Bool {
        let cleaned = phoneNumber.filter { $0.isNumber }
        return cleaned.count >= 10
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Header
                VStack(spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("Emergency Contact")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // Wearer's name (the person wearing the Watch)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    TextField("Your Name", text: $wearerName)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 36)
                        .disableAutocorrection(true)
                        .accessibilityLabel("Your name")
                        .accessibilityHint("Enter the name of the person wearing the watch")
                }
                .padding(.horizontal, 4)

                // Emergency contact name field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contact Name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    TextField("Contact Name", text: $contactName)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 36)
                        .disableAutocorrection(true)
                        .accessibilityLabel("Emergency contact name")
                }
                .padding(.horizontal, 4)

                // Phone field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Number")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    TextField("Phone", text: $phoneNumber)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 36)
                        .onChange(of: phoneNumber) { _, newValue in
                            phoneNumber = newValue.filter { $0.isNumber }
                        }
                        .accessibilityLabel("Emergency contact phone number")
                        .accessibilityHint("Enter at least 10 digits")
                }
                .padding(.horizontal, 4)

                // Validation error
                if showValidationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Text("Phone number required (10+ digits)")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: Phone number must be at least 10 digits")
                }

                // Success message
                if showSaveSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("Saved!")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Contact saved successfully")
                }

                // Save button
                Button(action: saveContact) {
                    Text("Save Contact")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Save emergency contact")
                .padding(.horizontal, 4)
                .padding(.top, 4)

                Divider()
                    .background(Color.gray.opacity(0.3))
                    .padding(.vertical, 4)

                // Test alert button
                Button(action: sendTestAlert) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Test Alert")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .accessibilityLabel("Send test alert")
                .accessibilityHint("Sends a test seizure alert to verify the system works")
                .padding(.horizontal, 4)

                // Test alert feedback
                if showTestAlertSent {
                    Text("Test alert sent!")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                        .accessibilityLabel("Test alert sent successfully")
                }
                if showTestAlertFailed {
                    Text("Test alert failed. Is iPhone nearby?")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .accessibilityLabel("Test alert failed. Make sure iPhone is nearby.")
                }

                Divider()
                    .background(Color.gray.opacity(0.3))
                    .padding(.vertical, 4)

                // Location permission status
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location Permission")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(locationStatusColor)
                            .frame(width: 8, height: 8)
                        Text(locationStatusText)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Location permission: \(locationStatusText)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                Spacer().frame(height: 20)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .onAppear {
            loadContact()
        }
    }

    // MARK: - Computed Properties

    private var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        default:
            return .yellow
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Authorized"
        case .denied, .restricted:
            return "Denied"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }

    // MARK: - Actions

    private func loadContact() {
        if let contact = EmergencyContact.load() {
            contactName = contact.name
            phoneNumber = contact.phoneNumber
        }
        wearerName = EmergencyContact.loadWearerName()
        // Clear the default placeholder so the field appears empty
        if wearerName == "the wearer" { wearerName = "" }
    }

    private func saveContact() {
        showValidationError = false
        showSaveSuccess = false

        guard !phoneNumber.isEmpty && isPhoneNumberValid else {
            showValidationError = true
            WKInterfaceDevice.current().play(.failure)
            return
        }

        let contact = EmergencyContact(
            name: contactName.isEmpty ? "Emergency Contact" : contactName,
            phoneNumber: phoneNumber
        )
        contact.save()
        EmergencyContact.saveWearerName(wearerName)

        showSaveSuccess = true
        WKInterfaceDevice.current().play(.success)
        logger.info("Emergency contact saved: \(contact.displayName)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showSaveSuccess = false
        }
    }

    private func sendTestAlert() {
        showTestAlertSent = false
        showTestAlertFailed = false

        guard let contact = EmergencyContact.load(), contact.isValid else {
            showValidationError = true
            WKInterfaceDevice.current().play(.failure)
            return
        }

        // Build a test alert and send it via WatchConnectivity
        let testAlert = AlertMessage(
            timestamp: Date(),
            latitude: locationManager.lastLocation?.coordinate.latitude ?? 0.0,
            longitude: locationManager.lastLocation?.coordinate.longitude ?? 0.0,
            contactName: contact.name,
            contactPhone: contact.phoneNumber,
            wearerName: EmergencyContact.loadWearerName()
        )

        WatchConnectivityManager.shared.sendAlert(testAlert) { success, error in
            if success {
                showTestAlertSent = true
                logger.info("Test alert sent successfully")
            } else {
                showTestAlertFailed = true
                logger.error("Test alert failed: \(error?.localizedDescription ?? "unknown")")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showTestAlertSent = false
                showTestAlertFailed = false
            }
        }

        WKInterfaceDevice.current().play(.notification)
    }
}

#Preview {
    SettingsView()
}
