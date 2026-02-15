import Foundation
import WatchConnectivity
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "PhoneConnectivity")

/// Phone-side WatchConnectivity manager that receives alerts from the watch
class PhoneConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = PhoneConnectivityManager()

    @Published var isConnected = false
    @Published var lastError: Error?
    @Published var lastAlert: AlertMessage?
    @Published var alertHistory: [AlertMessage] = []

    private var session: WCSession?
    private let messageQueue = DispatchQueue(label: "com.seizurealert.phone.connectivity")
    private let maxAlertHistory = 50

    // MARK: - Persistence Keys
    private static let alertHistoryKey = "alert_history"

    override init() {
        super.init()
        loadAlertHistory()
        setupSession()
    }

    // MARK: - Session Setup

    private func setupSession() {
        guard WCSession.isSupported() else {
            logger.warning("WCSession is not supported on this device")
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        messageQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.updateConnectionStatus()
                if let error = error {
                    logger.error("WCSession activation error: \(error.localizedDescription)")
                    self?.lastError = error
                }
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        messageQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = false
            }
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        messageQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = false
            }
        }
        // Reactivate the session
        session.activate()
    }

    // MARK: - Receiving Messages

    /// Handle live messages from the watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        messageQueue.async { [weak self] in
            if let alert = self?.decodeAlert(from: message) {
                DispatchQueue.main.async {
                    self?.handleReceivedAlert(alert)
                }
            }
        }
    }

    /// Handle messages with reply handler
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        messageQueue.async { [weak self] in
            if let alert = self?.decodeAlert(from: message) {
                DispatchQueue.main.async {
                    self?.handleReceivedAlert(alert)
                    replyHandler(["received": true])
                }
            } else {
                replyHandler(["received": false])
            }
        }
    }

    /// Handle transferred userInfo (for when phone was not immediately reachable)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        messageQueue.async { [weak self] in
            if let alert = self?.decodeAlert(from: userInfo) {
                DispatchQueue.main.async {
                    self?.handleReceivedAlert(alert)
                }
            }
        }
    }

    // MARK: - Alert Handling

    private func handleReceivedAlert(_ alert: AlertMessage) {
        lastAlert = alert

        // Add to history (keeping it bounded)
        alertHistory.insert(alert, at: 0)
        if alertHistory.count > maxAlertHistory {
            alertHistory.removeLast()
        }

        // Persist alert history
        saveAlertHistory()

        // Auto-sync: save the emergency contact from the Watch alert locally on the iPhone.
        // This way the iPhone learns the contact info without needing App Groups.
        let receivedContact = EmergencyContact(
            name: alert.contactName,
            phoneNumber: alert.contactPhone
        )
        if receivedContact.isValid {
            receivedContact.save()
            logger.info("Synced emergency contact from Watch: \(receivedContact.displayName)")
        }

        // Trigger alert (local notification + SMS)
        AlertService.shared.sendAlert(alert)

        logger.info("Received seizure alert from watch at \(alert.timestamp.description)")
    }

    // MARK: - Encoding/Decoding

    private func decodeAlert(from dict: [String: Any]) -> AlertMessage? {
        // First try the AlertMessage.from(dictionary:) convenience method
        if let alert = AlertMessage.from(dictionary: dict) {
            return alert
        }

        // Fallback: try direct JSON deserialization of the full dictionary
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            let alert = try JSONDecoder().decode(AlertMessage.self, from: jsonData)
            return alert
        } catch {
            logger.error("Failed to decode alert: \(error.localizedDescription)")
            lastError = error
            return nil
        }
    }

    // MARK: - Alert History Persistence

    private func saveAlertHistory() {
        do {
            let data = try JSONEncoder().encode(alertHistory)
            UserDefaults.standard.set(data, forKey: Self.alertHistoryKey)
            logger.debug("Saved \(self.alertHistory.count) alerts to history")
        } catch {
            logger.error("Failed to save alert history: \(error.localizedDescription)")
        }
    }

    private func loadAlertHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.alertHistoryKey) else { return }
        do {
            alertHistory = try JSONDecoder().decode([AlertMessage].self, from: data)
            logger.info("Loaded \(self.alertHistory.count) alerts from history")
        } catch {
            logger.error("Failed to load alert history: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection Status

    private func updateConnectionStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let session = self?.session else {
                self?.isConnected = false
                return
            }

            self?.isConnected = session.isReachable || session.isPaired
        }
    }

    /// Check if the paired watch is currently reachable
    func isWatchReachable() -> Bool {
        return session?.isReachable ?? false
    }

    /// Check if a watch is paired with this phone
    func isWatchPaired() -> Bool {
        return session?.isPaired ?? false
    }

    /// Clear alert history
    func clearAlertHistory() {
        DispatchQueue.main.async { [weak self] in
            self?.alertHistory.removeAll()
            UserDefaults.standard.removeObject(forKey: Self.alertHistoryKey)
            logger.info("Alert history cleared")
        }
    }
}
