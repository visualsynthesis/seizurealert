import SwiftUI

@main
struct SeizureAlertApp: App {
    
    init() {
        // Activate WCSession in the app initialization
        _ = PhoneConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            PhoneContentView()
        }
    }
}
