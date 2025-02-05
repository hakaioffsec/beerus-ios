import UIKit

enum PackageManager: String, CaseIterable {
    case cydia
    case sileo
    case zebra
    
    var scheme: String {
        switch self {
        case .cydia: 
            return "cydia"
        case .sileo:
            return "sileo"
        case .zebra: 
            return "zbra"
        }
    }

    func repositoryURL(for repoSource: String) -> URL? {
        switch self {
        case .cydia:
            return URL(string: "\(scheme)://url/\(repoSource)")
        case .sileo:
            return URL(string: "\(scheme)://source/\(repoSource)")
        case .zebra:
            return URL(string: "\(scheme)://sources/add/\(repoSource)")
        }
    }
    
    var title: String {
        switch self {
        case .cydia: 
            return "Add Cydia Repo"
        case .sileo: 
            return "Add Sileo Repo"
        case .zebra: 
            return "Add Zebra Repo"
        }
    }
    
    var isInstalled: Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    
    func open(source: String? = nil) {
        guard let sourceURL = source.flatMap(repositoryURL(for:)) ?? URL(string: "\(scheme)://"), UIApplication.shared.canOpenURL(sourceURL) else { return }
        UIApplication.shared.open(sourceURL)
    }
}
