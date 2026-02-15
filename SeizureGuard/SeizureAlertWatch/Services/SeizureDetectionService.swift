import Foundation
import CoreMotion
import os
#if os(watchOS)
import WatchKit
#endif

private let logger = Logger(subsystem: "com.seizureguard", category: "SeizureDetection")

/// Service that monitors Apple Watch accelerometer + gyroscope data
/// to detect seizure-like motion patterns (tonic-clonic seizures).
///
/// Detection approach:
/// 1. Continuously sample accelerometer data at 50Hz
/// 2. Calculate acceleration magnitude (removing gravity)
/// 3. Detect rapid, repetitive movements above a threshold
/// 4. If sustained for a configurable duration -> trigger alert
///
/// IMPORTANT: This is a simplified detection algorithm for educational purposes.
/// Real medical seizure detection requires clinical validation.
/// This should NOT be used as a sole medical device.

class SeizureDetectionService: ObservableObject {

    // MARK: - Published State

    @Published var isMonitoring = false
    @Published var seizureDetected = false
    @Published var currentAccelMagnitude: Double = 0.0

    // MARK: - Detection Parameters (tunable)

    /// Acceleration magnitude threshold (in g's) above which motion is considered "seizure-like"
    /// Typical tonic-clonic seizures produce rapid, high-magnitude limb movements
    private let accelerationThreshold: Double = 2.0

    /// How many seconds of sustained high-magnitude motion before triggering
    private let sustainedDurationRequired: TimeInterval = 5.0

    /// Sampling rate in Hz
    private let sampleRate: TimeInterval = 1.0 / 50.0  // 50 Hz

    /// Percentage of samples in the window that must exceed threshold
    private let activationRatio: Double = 0.6

    // MARK: - Internal State

    private let motionManager = CMMotionManager()
    private var recentMagnitudes: [Double] = []
    private let windowSize = 250  // 5 seconds at 50Hz
    private var sustainedStartTime: Date?

    /// Dedicated queue for motion processing to keep the main thread responsive
    private let processingQueue = OperationQueue()

    // MARK: - Lifecycle

    init() {
        processingQueue.name = "com.seizureguard.motion-processing"
        processingQueue.maxConcurrentOperationCount = 1
        processingQueue.qualityOfService = .userInteractive
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Start monitoring motion data for seizure-like patterns
    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else {
            logger.warning("Accelerometer not available on this device")
            return
        }

        guard !isMonitoring else {
            logger.info("Monitoring already active, ignoring duplicate start")
            return
        }

        // Reset state
        recentMagnitudes.removeAll()
        sustainedStartTime = nil
        seizureDetected = false

        // Configure accelerometer
        motionManager.accelerometerUpdateInterval = sampleRate

        // Process accelerometer data on a dedicated queue to avoid main-thread jank
        motionManager.startAccelerometerUpdates(to: processingQueue) { [weak self] data, error in
            guard let self = self, let data = data else {
                if let error = error {
                    logger.error("Accelerometer error: \(error.localizedDescription)")
                }
                return
            }
            self.processAccelerometerData(data)
        }

        isMonitoring = true
        logger.info("Seizure detection monitoring started")
    }

    /// Stop monitoring motion data
    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        recentMagnitudes.removeAll()
        sustainedStartTime = nil
        logger.info("Seizure detection monitoring stopped")
    }

    /// Reset after a seizure alert (user cancelled or alert was sent)
    func resetAfterAlert() {
        seizureDetected = false
        recentMagnitudes.removeAll()
        sustainedStartTime = nil
    }

    // MARK: - Motion Processing

    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // Calculate total acceleration magnitude
        // Subtract ~1g for gravity (when stationary, magnitude ~= 1.0)
        let acc = data.acceleration
        let magnitude = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)

        // The "user acceleration" portion (removing gravity baseline)
        let userMagnitude = abs(magnitude - 1.0)

        // Update UI-facing value on main thread
        DispatchQueue.main.async { [weak self] in
            self?.currentAccelMagnitude = userMagnitude
        }

        // Add to sliding window
        recentMagnitudes.append(userMagnitude)
        if recentMagnitudes.count > windowSize {
            recentMagnitudes.removeFirst()
        }

        // Only analyze once we have a full window
        guard recentMagnitudes.count >= windowSize else { return }

        analyzeWindow()
    }

    private func analyzeWindow() {
        // Count how many samples exceed the threshold
        let exceedingCount = recentMagnitudes.filter { $0 > accelerationThreshold }.count
        let ratio = Double(exceedingCount) / Double(recentMagnitudes.count)

        if ratio >= activationRatio {
            // High-magnitude motion detected
            if sustainedStartTime == nil {
                sustainedStartTime = Date()
            }

            // Check if sustained long enough
            if let startTime = sustainedStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= sustainedDurationRequired && !seizureDetected {
                    triggerSeizureDetection()
                }
            }
        } else {
            // Motion subsided — reset the sustained timer
            sustainedStartTime = nil
        }
    }

    private func triggerSeizureDetection() {
        logger.critical("Seizure-like motion detected!")

        // Update published state on main thread
        DispatchQueue.main.async { [weak self] in
            self?.seizureDetected = true
        }

        // Haptic feedback to alert the user
        #if os(watchOS)
        DispatchQueue.main.async {
            WKInterfaceDevice.current().play(.notification)
        }
        #endif
    }
}
