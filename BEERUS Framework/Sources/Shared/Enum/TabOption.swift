import UIKit

enum TabOption: String, CaseIterable {
    case home = "Home"
    case setupFrida = "Setup Frida"

    var icon: String {
        switch self {
        case .home: return "house"
        case .setupFrida: return "frida"
        }
    }
}
