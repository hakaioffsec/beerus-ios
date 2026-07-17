import SwiftUI

@main
struct JailbreakDetectorApp: App {
    init() {
        // ponytail: run checks immediately on launch for SSH testing
        _ = JBDetector.runAllChecks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
