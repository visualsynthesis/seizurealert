import SwiftUI
import WatchKit
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "CountdownView")

struct CountdownView: View {
    static let countdownDuration: Double = 10.0

    @State private var remainingTime: Double = CountdownView.countdownDuration
    @State private var timerActive = true
    @State private var timer: Timer?
    @State private var startDate: Date?
    @State private var lastHapticSecond: Int = Int(CountdownView.countdownDuration)

    var onCountdownComplete: () -> Void
    var onCancelled: () -> Void

    @State private var emergencyContact: EmergencyContact?

    var progressPercentage: Double {
        (CountdownView.countdownDuration - remainingTime) / CountdownView.countdownDuration
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Warning Text
                VStack(spacing: 8) {
                    Text("Seizure Detected")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.red)
                        .accessibilityAddTraits(.isHeader)

                    Text("Emergency alert sending")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                Spacer()

                // Circular Progress with Countdown
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 4)

                    // Progress circle
                    Circle()
                        .trim(from: 0, to: progressPercentage)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.red, .orange]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: progressPercentage)

                    // Timer text in center
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", max(0, remainingTime)))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        Text("seconds")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 100, height: 100)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Countdown timer")
                .accessibilityValue("\(Int(ceil(remainingTime))) seconds remaining")

                // Contact Info
                if let contact = emergencyContact {
                    VStack(spacing: 4) {
                        Text("Notifying")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.gray)

                        Text(contact.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Will notify \(contact.name)")
                } else {
                    Text("No contact configured")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.yellow)
                        .padding(.vertical, 6)
                }

                Spacer()

                // Cancel Button
                Button(action: cancelAlert) {
                    Text("I'M OK")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Cancel seizure alert")
                .accessibilityHint("Double tap to confirm you are okay and cancel the emergency alert")
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .onAppear {
            emergencyContact = EmergencyContact.load()
            startCountdown()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    private func startCountdown() {
        let start = Date()
        startDate = start
        lastHapticSecond = Int(CountdownView.countdownDuration)

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard timerActive, let start = startDate else { return }

            // Compute remaining time from wall clock to avoid float drift
            let elapsed = Date().timeIntervalSince(start)
            let newRemaining = CountdownView.countdownDuration - elapsed
            remainingTime = max(0, newRemaining)

            // Haptic feedback each whole second boundary
            let currentSecond = Int(ceil(remainingTime))
            if currentSecond < lastHapticSecond && remainingTime > 0 {
                lastHapticSecond = currentSecond
                WKInterfaceDevice.current().play(.notification)
            }

            // Check if countdown complete
            if remainingTime <= 0 {
                stopCountdown()
                timerActive = false
                logger.info("Countdown complete, sending alert")
                onCountdownComplete()
            }
        }
    }

    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }

    private func cancelAlert() {
        stopCountdown()
        timerActive = false

        // Strong haptic feedback for cancellation
        WKInterfaceDevice.current().play(.success)
        logger.info("Alert cancelled by user")

        onCancelled()
    }
}

#Preview {
    CountdownView(
        onCountdownComplete: {},
        onCancelled: {}
    )
}
