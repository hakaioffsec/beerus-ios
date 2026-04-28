import UIKit

enum JailbreakRoot {
    case rootful
    case rootless

    var path: String {
        switch self {
        case .rootful: return "/"
        case .rootless: return "/var/jb/"
        }
    }
}

final class BeerusStrings {

    static let rootType: JailbreakRoot = {
        FileManager.default.fileExists(atPath: "/var/jb") ? .rootless : .rootful
    }()

    static var root: String {
        rootType.path
    }
    
    static var fridaDaemonPath: String {
        root + "Library/LaunchDaemons/re.frida.server.plist"
    }

    static var fridaServerPath: String {
        root + "usr/sbin/frida-server"
    }
    
    static var tmp: String {
        root + "tmp/"
    }

    static var launchctlBin: String {
        root + "usr/bin/launchctl"
    }
    
    static var dpkgBin: String {
        root + "usr/bin/dpkg"
    }
    
}
