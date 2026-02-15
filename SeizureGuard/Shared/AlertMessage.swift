import Foundation
import CoreLocation

/// Message sent from Watch → iPhone when a seizure alert is triggered
struct AlertMessage: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let contactName: String
    let contactPhone: String
    /// The name of the person wearing the Watch (shown in the SMS)
    let wearerName: String

    /// Human-readable location string for the SMS body
    var locationString: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    /// Google Maps link for the recipient to open
    var mapsLink: String {
        "https://maps.google.com/?q=\(latitude),\(longitude)"
    }

    /// The full SMS body to send
    var smsBody: String {
        """
        SEIZURE ALERT

        A seizure has been detected on \(wearerName)'s Apple Watch.

        Location: \(locationString)
        Map: \(mapsLink)

        Time: \(formattedTime)

        Please check on them immediately.
        """
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    /// Convert to dictionary for WatchConnectivity transfer.
    /// Encodes the entire AlertMessage as JSON Data under the "alertMessage" key.
    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else {
            return [:]
        }
        return ["alertMessage": data]
    }

    /// Reconstruct from WatchConnectivity dictionary.
    /// Expects the JSON Data under the "alertMessage" key (matching toDictionary).
    static func from(dictionary: [String: Any]) -> AlertMessage? {
        guard let data = dictionary["alertMessage"] as? Data else { return nil }
        return try? JSONDecoder().decode(AlertMessage.self, from: data)
    }
}
