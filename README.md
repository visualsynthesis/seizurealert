# SeizureGuard — Apple Watch Seizure Detection & Alert App

An Apple Watch app that detects seizure-like motion, gives the wearer 10 seconds to cancel, then automatically alerts an emergency contact via local notification and pre-composed SMS with live GPS location.

> **Medical Disclaimer:** This app uses a simplified motion-detection algorithm and is NOT a certified medical device. It should not be relied upon as the sole means of seizure detection. Always consult a healthcare professional for medical monitoring needs.

---

## How It Works

1. **Monitoring** — The watch continuously reads accelerometer data at 50Hz on a dedicated background queue
2. **Detection** — When rapid, sustained high-magnitude movements are detected for 5+ seconds (consistent with tonic-clonic seizures), an alert triggers
3. **Countdown** — The user sees a 10-second countdown with a large "I'M OK" cancel button and strong haptic pulses each second
4. **Alert** — If not cancelled, the watch sends the user's GPS coordinates to the paired iPhone, which fires a critical local notification immediately and opens a pre-composed SMS to the configured emergency contact with a Google Maps link
5. **Auto-Restart** — Monitoring automatically resumes after an alert is sent or cancelled

---

## Project Structure

```
SeizureGuard/
├── PrivacyInfo.xcprivacy            ← Required privacy manifest (iOS 17+)
├── Shared/                          ← Models used by both targets
│   ├── EmergencyContact.swift       ← Contact name + phone storage
│   └── AlertMessage.swift           ← Alert payload with location
│
├── SeizureAlertWatch/               ← watchOS App
│   ├── SeizureAlertWatchApp.swift   ← App entry point
│   ├── Resources/
│   │   ├── Info.plist               ← Permissions & background modes
│   │   └── SeizureAlertWatch.entitlements
│   ├── Views/
│   │   ├── MainView.swift           ← Home screen with monitoring toggle
│   │   ├── CountdownView.swift      ← 10-second cancel countdown
│   │   └── SettingsView.swift       ← Emergency contact setup
│   └── Services/
│       ├── SeizureDetectionService.swift  ← CoreMotion seizure detection
│       ├── LocationManager.swift          ← GPS location
│       └── WatchConnectivityManager.swift ← Watch → iPhone messaging
│
└── SeizureAlertPhone/               ← Companion iOS App
    ├── SeizureAlertApp.swift        ← App entry point
    ├── Resources/
    │   ├── Info.plist               ← Permissions
    │   └── SeizureAlertPhone.entitlements
    ├── Views/
    │   └── PhoneContentView.swift   ← Settings + alert log
    └── Services/
        ├── PhoneConnectivityManager.swift ← iPhone ← Watch messaging
        └── AlertService.swift             ← Notifications + SMS sending
```

---

## Setup Guide (Step by Step)

### Prerequisites

- **Mac** with macOS 14 (Sonoma) or later
- **Xcode 15** or later (free from the Mac App Store)
- **Apple Developer Account** (free tier works for personal device testing)
- **iPhone** paired with an **Apple Watch** (for real testing)

### Step 1: Create the Xcode Project

1. Open Xcode → **File → New → Project**
2. Select **watchOS** tab → choose **App**
3. Configure:
   - **Product Name:** `SeizureAlert`
   - **Team:** Select your Apple ID
   - **Organization Identifier:** `com.seizureguard` (or your own)
   - **Interface:** SwiftUI
   - **Watch-only App:** **No** (we need the companion iPhone app)
   - **Include Tests:** Optional
4. Click **Create** and save somewhere convenient

### Step 2: Add Source Files

1. In Xcode's project navigator, right-click the watch app folder → **Add Files to "SeizureAlert"**
2. Add all files from `SeizureAlertWatch/` maintaining the folder structure
3. Do the same for `SeizureAlertPhone/` files in the iPhone target
4. Add files from `Shared/` to **both** targets:
   - Select each shared file → in the File Inspector (right panel) → under **Target Membership**, check both the Watch and iPhone targets
5. Add `PrivacyInfo.xcprivacy` to **both** targets

### Step 3: Configure Info.plist & Permissions

The required Info.plist files are included in each target's `Resources/` folder. If Xcode generates its own, copy the permission keys from the provided files:

**Watch App** requires:
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSMotionUsageDescription`
- Background modes: `workout-processing`, `fetch`

**iPhone App** requires:
- `NSLocationWhenInUseUsageDescription`

### Step 4: Set Up App Groups (Optional)

App Groups allow the Watch and iPhone to share data directly. Without them, contact info syncs automatically via WatchConnectivity when alerts are sent.

1. In the project navigator, click the **SeizureAlert** project (blue icon at top)
2. Select the **Watch App** target → **Signing & Capabilities** → **+ Capability** → **App Groups**
3. Add: `group.com.seizureguard.app`
4. Repeat for the **iPhone** target
5. Update the `UserDefaults.appGroup` in `EmergencyContact.swift` to use the App Group suite

### Step 5: Enable Background Modes (Watch)

1. Select the Watch App target
2. **Signing & Capabilities** → **+ Capability** → **Background Modes**
3. Enable:
   - **Workout processing** (keeps the app alive for continuous motion monitoring)
   - **Background fetch**

### Step 6: Enable Critical Alerts (Recommended)

To use critical notifications (which play sound even in Do Not Disturb):
1. Request a Critical Alerts entitlement from Apple via your developer account
2. Add the `com.apple.developer.usernotifications.critical-alerts` entitlement

Without this, notifications will still work but won't override silent mode.

### Step 7: Build & Run

1. Connect your iPhone to your Mac
2. In Xcode's device selector (top bar), choose your Apple Watch
3. Click **Run** or press `Cmd + R`
4. On first launch, the watch will ask for Location, Motion, and Notification permissions — **Allow** all
5. Open the **Settings** screen on the watch and enter your emergency contact's info

### Step 8: Test It

1. Start monitoring from the main screen
2. Shake your wrist rapidly for ~8 seconds to simulate detection
3. You should see the countdown screen appear
4. Tap "I'M OK" to cancel, or let it count down to test the full alert flow

---

## Tuning the Detection Algorithm

The seizure detection parameters in `SeizureDetectionService.swift` can be adjusted:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `accelerationThreshold` | 2.0 g | How intense the motion must be |
| `sustainedDurationRequired` | 5.0 sec | How long the motion must last |
| `sampleRate` | 50 Hz | How often we read the accelerometer |
| `activationRatio` | 0.6 | What % of samples must exceed threshold |

**Tips:**
- **Too many false positives?** Increase `accelerationThreshold` to 2.5 or increase `sustainedDurationRequired` to 8 seconds
- **Not detecting?** Lower `accelerationThreshold` to 1.5 or reduce `activationRatio` to 0.4
- Test with someone who has medical knowledge of the seizure types you want to detect

---

## Architecture Notes

- **Logging** — All files use `os.Logger` with the subsystem `com.seizureguard` and per-file categories. View logs in Xcode console or Console.app by filtering on this subsystem.
- **Threading** — Accelerometer data is processed on a dedicated `OperationQueue` (not the main thread) to avoid UI jank at 50Hz. Only UI-facing `@Published` properties are updated on main.
- **Alert Delivery** — Uses a multi-layer approach: (1) critical local notification fires immediately with no user interaction, (2) SMS compose view opens for manual send. For fully automatic SMS, integrate a backend service like Twilio.
- **Accessibility** — All interactive elements have VoiceOver labels and hints.
- **Privacy** — Includes `PrivacyInfo.xcprivacy` declaring location data usage and UserDefaults API access (required for App Store since iOS 17).

---

## Future Enhancements

- **Automatic SMS via backend** — Set up a simple server (e.g., Twilio + Firebase Cloud Functions) to send SMS without user interaction
- **HealthKit integration** — Log seizure events to Apple Health for sharing with doctors
- **Heart rate monitoring** — Add heart rate spike detection as a secondary signal
- **Multiple contacts** — Alert a list of emergency contacts instead of just one
- **Watch complications** — Show monitoring status directly on the watch face
- **Siri Shortcuts** — "Hey Siri, start seizure monitoring"
- **HKWorkoutSession** — Use a workout session for guaranteed background execution

---

## Troubleshooting

**"Accelerometer not available"**
→ You're running in the Simulator. CoreMotion requires a physical Apple Watch.

**SMS not sending**
→ The iPhone app must be installed and the watch must be paired. Check that WatchConnectivity shows "Connected" in the iPhone app.

**Notification not appearing**
→ Make sure you granted notification permissions. Check Settings → Notifications → SeizureGuard.

**Location shows (0, 0)**
→ Make sure you granted location permissions. Go to Watch → Settings → Privacy → Location Services → SeizureGuard → While Using.

**Alert fires too easily / not at all**
→ Adjust the detection parameters (see "Tuning" section above).

---

Built with SwiftUI, CoreMotion, CoreLocation, WatchConnectivity, UserNotifications, MessageUI, and os.Logger.
