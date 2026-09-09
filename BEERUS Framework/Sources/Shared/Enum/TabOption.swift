import UIKit

enum TabOption: String, CaseIterable {
    case home = "Home"
    case setupFrida = "Setup Frida"
    case ipaExtractor = "IPA Extractor"
    case memoryDump = "Memory Dump"
    case lldbServer = "LLDB Server"
    case proxyProfiles = "Proxy Profiles"
    case terminal = "Terminal"
    case plistReader = "Plist Reader"
    case scriptEditor = "Script Editor"
    case appStore = "App Store"
    case jailbreakBypass = "Cloak"
    case sandboxExfiltration = "Sandbox Exf/"

    var icon: String {
        switch self {
        case .home: return "house"
        case .setupFrida: return "frida"
        case .ipaExtractor: return "ipa-extractor"
        case .memoryDump: return "memorychip"
        case .lldbServer: return "ant.fill"
        case .proxyProfiles: return "network"
        case .terminal: return "terminal"
        case .plistReader: return "doc.text.fill"
        case .scriptEditor: return "scroll"
        case .appStore: return "cart.fill"
        case .jailbreakBypass: return "shield.slash"
        case .sandboxExfiltration: return "shippingbox.fill"
        }
    }

    var image: UIImage? {
        switch self {
        case .terminal:
            return UIImage(systemName: "terminal.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .memoryDump:
            return UIImage(systemName: "memorychip")?
                .withRenderingMode(.alwaysTemplate)
        case .plistReader:
            return UIImage(systemName: "doc.text.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .ipaExtractor:
            return UIImage(systemName: "arrow.down.app.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .lldbServer:
            return UIImage(systemName: "ant.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .proxyProfiles:
            return UIImage(systemName: "wifi")?
                .withRenderingMode(.alwaysTemplate)
        case .scriptEditor:
            return UIImage(systemName: "scroll.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .appStore:
            return UIImage(systemName: "cart.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .jailbreakBypass:
            return UIImage(systemName: "shield.slash.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .sandboxExfiltration:
            return UIImage(systemName: "shippingbox.fill")?
                .withRenderingMode(.alwaysTemplate)
        default:
            return UIImage(named: icon)?
                .withRenderingMode(.alwaysTemplate)
        }
    }
}
