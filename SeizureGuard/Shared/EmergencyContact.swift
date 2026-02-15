import Foundation

/// Model representing the user's emergency contact
struct EmergencyContact: Codable {
    var name: String
    var phoneNumber: String

    /// Format for display
    var displayName: String {
        name.isEmpty ? phoneNumber : name
    }

    /// Validates that the contact has at minimum a phone number
    var isValid: Bool {
        !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns the phone number formatted for an sms: URL scheme
    var smsURLString: String {
        let cleaned = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return cleaned
    }
}

// MARK: - UserDefaults Storage

extension EmergencyContact {
    private static let storageKey = "emergency_contact"
    private static let wearerNameKey = "wearer_name"

    /// Save to standard UserDefaults (local to this device)
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.appGroup.set(data, forKey: Self.storageKey)
        }
    }

    /// Load from standard UserDefaults (local to this device)
    static func load() -> EmergencyContact? {
        guard let data = UserDefaults.appGroup.data(forKey: Self.storageKey),
              let contact = try? JSONDecoder().decode(EmergencyContact.self, from: data) else {
            return nil
        }
        return contact
    }

    /// Save the wearer's name (the person wearing the Watch)
    static func saveWearerName(_ name: String) {
        UserDefaults.appGroup.set(name, forKey: wearerNameKey)
    }

    /// Load the wearer's name, defaulting to "the wearer" if not set
    static func loadWearerName() -> String {
        let name = UserDefaults.appGroup.string(forKey: wearerNameKey) ?? ""
        return name.isEmpty ? "the wearer" : name
    }
}

// MARK: - Standard UserDefaults (no App Groups needed)

extension UserDefaults {
    /// Uses standard UserDefaults — no paid developer account or App Groups required.
    /// Each device (Watch / iPhone) stores its own copy locally.
    /// Contact info syncs automatically when alerts are sent via WatchConnectivity.
    static let appGroup = UserDefaults.standard
}
