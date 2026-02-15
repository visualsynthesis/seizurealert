import SwiftUI
import WatchKit
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "MainView")

struct MainView: View {
    @StateObject private var detectionService = SeizureDetectionService()
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var navigateToCountdown = false
    @State private var isPulsing = false
    @State private var showAlertError = false
    @State private var alertErrorMessage = ""
    @State private var showNoContactWarning = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text("SeizureGuard")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Text(detectionService.isMonitoring ? "Active" : "Inactive")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(detectionService.isMonitoring ? .green : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    // Pulsing status indicator
                    ZStack {
                        if detectionService.isMonitoring {
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                                .frame(width: 80, height: 80)
                                .scaleEffect(isPulsing ? 1.3 : 0.9)
                                .opacity(isPulsing ? 0.0 : 0.6)
                        }

                        Circle()
                            .fill(detectionService.isMonitoring ? Color.green : Color.gray)
                            .frame(width: 60, height: 60)

                        Image(systemName: detectionService.isMonitoring ? "heart.fill" : "heart")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .accessibilityLabel(detectionService.isMonitoring ? "Monitoring active" : "Monitoring inactive")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onChange(of: detectionService.isMonitoring) { _, isActive in
                        if isActive {
                            withAnimation(
                                .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                            ) {
                                isPulsing = true
                            }
                        } else {
                            isPulsing = false
                        }
                    }

                    // Toggle button
                    Button(action: toggleMonitoring) {
                        Text(detectionService.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(detectionService.isMonitoring ? Color.red : Color.green)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel(detectionService.isMonitoring ? "Stop seizure monitoring" : "Start seizure monitoring")
                    .accessibilityHint("Double tap to toggle monitoring")
                    .padding(.horizontal, 8)

                    // Debug readout
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accel")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.gray)
                            Text(String(format: "%.2f g", detectionService.currentAccelMagnitude))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Status")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.gray)
                            Text(detectionService.isMonitoring ? "Running" : "Idle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(detectionService.isMonitoring ? .green : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)

                    Spacer()

                    // Settings link
                    NavigationLink(destination: SettingsView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Settings")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                    }
                    .accessibilityLabel("Open settings")
                    .accessibilityHint("Configure emergency contact and permissions")
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
            .navigationDestination(isPresented: $navigateToCountdown) {
                CountdownView(
                    onCountdownComplete: handleCountdownComplete,
                    onCancelled: handleCountdownCancelled
                )
            }
        }
        .onAppear {
            locationManager.requestPermission()
        }
        .onChange(of: detectionService.seizureDetected) { _, newValue in
            if newValue {
                // Check for valid emergency contact before proceeding
                guard let contact = EmergencyContact.load(), contact.isValid else {
                    showNoContactWarning = true
                    detectionService.resetAfterAlert()
                    logger.warning("Seizure detected but no emergency contact configured")
                    return
                }
                // Fetch location immediately when seizure detected
                locationManager.requestCurrentLocation()
                navigateToCountdown = true
                WKInterfaceDevice.current().play(.notification)
            }
        }
        .alert("No Emergency Contact", isPresented: $showNoContactWarning) {
            Button("Open Settings") {
                // Navigation to settings handled by user
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("A seizure was detected but no emergency contact is configured. Please set one up in Settings.")
        }
        .alert("Alert Failed", isPresented: $showAlertError) {
            Button("Retry") {
                handleCountdownComplete()
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(alertErrorMessage)
        }
    }

    private func toggleMonitoring() {
        if detectionService.isMonitoring {
            detectionService.stopMonitoring()
        } else {
            detectionService.startMonitoring()
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func handleCountdownComplete() {
        // Build the alert message with current location
        let contact = EmergencyContact.load() ?? EmergencyContact(name: "Unknown", phoneNumber: "")
        let lat = locationManager.lastLocation?.coordinate.latitude ?? 0.0
        let lon = locationManager.lastLocation?.coordinate.longitude ?? 0.0

        let alertMessage = AlertMessage(
            timestamp: Date(),
            latitude: lat,
            longitude: lon,
            contactName: contact.name,
            contactPhone: contact.phoneNumber,
            wearerName: EmergencyContact.loadWearerName()
        )

        // Send via WatchConnectivity to the iPhone
        connectivityManager.sendAlert(alertMessage) { success, error in
            if success {
                logger.info("Alert sent to iPhone successfully")
            } else {
                let errorDesc = error?.localizedDescription ?? "iPhone may not be reachable"
                logger.error("Failed to send alert: \(errorDesc)")
                alertErrorMessage = "Could not send alert to iPhone: \(errorDesc)"
                showAlertError = true
            }
        }

        detectionService.resetAfterAlert()
        navigateToCountdown = false

        // Auto-restart monitoring after alert is processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !detectionService.isMonitoring {
                detectionService.startMonitoring()
                logger.info("Monitoring auto-restarted after alert")
            }
        }
    }

    private func handleCountdownCancelled() {
        detectionService.resetAfterAlert()
        navigateToCountdown = false

        // Auto-restart monitoring after cancellation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !detectionService.isMonitoring {
                detectionService.startMonitoring()
                logger.info("Monitoring auto-restarted after cancellation")
            }
        }
    }
}

#Preview {
    MainView()
}
