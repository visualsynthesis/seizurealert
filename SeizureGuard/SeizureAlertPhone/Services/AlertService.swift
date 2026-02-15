import Foundation
import MessageUI
import UIKit
import UserNotifications
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "AlertService")

/// Service that sends alerts when a seizure is detected.
/// Uses a multi-layered approach:
/// 1. Local notification (fires immediately, no user interaction needed)
/// 2. SMS via MFMessageComposeViewController (requires user tap)
/// 3. Fallback to sms: URL scheme if compose view unavailable
class AlertService {

    static let shared = AlertService()

    private init() {
        requestNotificationPermission()
    }

    // MARK: - Notification Permission

    /// Request notification authorization on first use
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                logger.info("Notification permission granted")
            } else if let error = error {
                logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Public API

    /// Send an alert using all available channels
    func sendAlert(_ alert: AlertMessage) {
        let contact = EmergencyContact(name: alert.contactName, phoneNumber: alert.contactPhone)
        guard contact.isValid else {
            logger.warning("No valid contact in alert message")
            return
        }

        // 1. Always fire a local notification immediately (no user interaction needed)
        sendLocalNotification(alert, to: contact)

        // 2. Attempt SMS (requires user interaction but delivers the message)
        sendSMS(alert, to: contact)

        logger.info("Alert dispatched for contact: \(contact.displayName)")
    }

    // MARK: - Local Notification (Automatic, no user interaction)

    private func sendLocalNotification(_ alert: AlertMessage, to contact: EmergencyContact) {
        let content = UNMutableNotificationContent()
        content.title = "SEIZURE ALERT"
        content.body = "A seizure was detected. Contact \(contact.displayName) at \(contact.phoneNumber). Location: \(alert.mapsLink)"
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.categoryIdentifier = "SEIZURE_ALERT"

        // Add a "Call" action so the user can tap to call the contact directly
        let callAction = UNNotificationAction(
            identifier: "CALL_CONTACT",
            title: "Call \(contact.displayName)",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "SEIZURE_ALERT",
            actions: [callAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Fire immediately
        let request = UNNotificationRequest(
            identifier: "seizure-alert-\(alert.timestamp.timeIntervalSince1970)",
            content: content,
            trigger: nil  // nil trigger = deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to deliver local notification: \(error.localizedDescription)")
            } else {
                logger.info("Local notification delivered successfully")
            }
        }
    }

    // MARK: - SMS

    private func sendSMS(_ alert: AlertMessage, to contact: EmergencyContact) {
        DispatchQueue.main.async {
            guard MFMessageComposeViewController.canSendText() else {
                // Fallback to sms: URL scheme
                self.fallbackToURLScheme(alert: alert, contact: contact)
                return
            }

            let messageVC = MFMessageComposeViewController()
            messageVC.body = alert.smsBody
            messageVC.recipients = [contact.phoneNumber]

            // Present from the key window
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                messageVC.messageComposeDelegate = SMSDelegate.shared
                rootVC.present(messageVC, animated: true)
            } else {
                logger.warning("Could not find root view controller to present SMS")
                self.fallbackToURLScheme(alert: alert, contact: contact)
            }
        }
    }

    private func fallbackToURLScheme(alert: AlertMessage, contact: EmergencyContact) {
        let encoded = alert.smsBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phone = contact.smsURLString

        if let url = URL(string: "sms:\(phone)?body=\(encoded)") {
            DispatchQueue.main.async {
                UIApplication.shared.open(url) { success in
                    if success {
                        logger.info("SMS URL scheme opened successfully")
                    } else {
                        logger.error("Failed to open SMS URL scheme")
                    }
                }
            }
        }
    }
}

// MARK: - MFMessageComposeViewControllerDelegate

/// Standalone delegate so the compose view can dismiss itself
private class SMSDelegate: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = SMSDelegate()

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true)

        switch result {
        case .sent:
            logger.info("SMS sent successfully")
        case .cancelled:
            logger.warning("SMS cancelled by user")
        case .failed:
            logger.error("SMS failed to send")
        @unknown default:
            break
        }
    }
}
