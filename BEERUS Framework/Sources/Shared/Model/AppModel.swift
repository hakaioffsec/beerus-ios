import Foundation

struct AppModel {
    let name: String
    let bundleIdentifier: String
    let bundlePath: String
    let executablePath: String
    var pid: UInt = 0

    var isRunning: Bool { pid != 0 }
}
