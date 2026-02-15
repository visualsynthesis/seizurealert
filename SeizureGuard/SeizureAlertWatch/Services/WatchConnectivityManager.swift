import Foundation
import WatchConnectivity
import os

private let logger = Logger(subsystem: "com.seizureguard", category: "WatchConnectivity")

/// Watch-side WatchConnectivity manager that handles sending alerts to the paired iPhone
@available(watchOS 6.0, *)
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchConnectivityManager()

    @Published var isConnected = false
    @Published var lastError: Error?

    private var session: WCSession?
    private let messageQueue = DispatchQueue(label: "com.seizurealert.watch.connectivity")

    override init() {
        super.init()
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

    // Note: sessionDidBecomeInactive and sessionDidDeactivate are iOS-only
    // and are not required on watchOS. The WCSessionDelegate protocol on watchOS
    // only requires session(_:activationDidCompleteWith:error:).

    // MARK: - Sending Alerts

    /// Sends an AlertMessage to the paired iPhone with high priority
    /// Falls back to transferUserInfo if the phone is not reachable
    func sendAlert(_ alert: AlertMessage, completion: @escaping (Bool, Error?) -> Void) {
        messageQueue.async { [weak self] in
            guard let session = self?.session, session.isReachable else {
                logger.info("Phone not reachable, falling back to transferUserInfo")
                // Phone is not reachable, try fallback
                self?.sendAlertViaUserInfo(alert, completion: completion)
                return
            }

            do {
                let messageData = try self?.encodeAlert(alert) ?? [:]
                session.sendMessage(messageData, replyHandler: { _ in
                    DispatchQueue.main.async {
                        logger.info("Alert sent to iPhone via live message")
                        completion(true, nil)
                    }
                }) { error in
                    logger.warning("Live message failed, falling back: \(error.localizedDescription)")
                    // If high-priority send fails, fallback to transferUserInfo
                    self?.sendAlertViaUserInfo(alert) { success, error in
                        DispatchQueue.main.async {
                            completion(success, error)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    logger.error("Failed to encode alert: \(error.localizedDescription)")
                    self?.lastError = error
                    completion(false, error)
                }
            }
        }
    }

    /// Fallback method: transfers alert via userInfo dictionary
    private func sendAlertViaUserInfo(_ alert: AlertMessage, completion: @escaping (Bool, Error?) -> Void) {
        messageQueue.async { [weak self] in
            do {
                let userInfo = try self?.encodeAlert(alert) ?? [:]
                self?.session?.transferUserInfo(userInfo)
                DispatchQueue.main.async {
                    logger.info("Alert queued via transferUserInfo")
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    logger.error("Failed to transfer user info: \(error.localizedDescription)")
                    self?.lastError = error
                    completion(false, error)
                }
            }
        }
    }

    // MARK: - Encoding/Decoding

    /// Encodes the alert using AlertMessage.toDictionary() so the phone-side
    /// AlertMessage.from(dictionary:) can decode it on the first pass (no fallback needed).
    private func encodeAlert(_ alert: AlertMessage) throws -> [String: Any] {
        let dict = alert.toDictionary()
        guard !dict.isEmpty else {
            throw NSError(domain: "WatchConnectivityManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode alert"])
        }
        return dict
    }

    // MARK: - Connection Status

    private func updateConnectionStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let session = self?.session else {
                self?.isConnected = false
                return
            }

            self?.isConnected = session.isReachable || session.activationState == .activated
        }
    }

    /// Check if the paired iPhone is currently reachable
    func isPhoneReachable() -> Bool {
        return session?.isReachable ?? false
    }

    /// Check if the session is activated (iPhone companion app available)
    func isSessionActivated() -> Bool {
        return session?.activationState == .activated
    }
}
