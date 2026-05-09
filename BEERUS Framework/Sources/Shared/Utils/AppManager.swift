import Foundation
  

class AppManager {
    struct AppInfo {
        let name: String
        let caminho: String
        let icone: String
        let plists: [String]
    }
    
    func getApps() -> [String: AppInfo] {
        let appDirectory = "/private/var/containers/Bundle/Application/"
        let fileManager = FileManager.default
        var result: [String: AppInfo] = [:]

        guard let appUUIDs = try? fileManager.contentsOfDirectory(atPath: appDirectory) else {
<<<<<<< HEAD
            print("Erro ao acessar o diretório de aplicativos.")
=======
            print("Failed to access app directory.")
>>>>>>> ae68300 (feat: add script editor, and frida integration)
            return result
        }

        for uuid in appUUIDs {
            let uuidPath = appDirectory + uuid
            guard let contents = try? fileManager.contentsOfDirectory(atPath: uuidPath) else { continue }

            guard let appFolder = contents.first(where: { $0.hasSuffix(".app") }) else { continue }
            
            let name = appFolder.components(separatedBy: ".app").first ?? ""
            let appPath = "\(uuidPath)/\(appFolder)"
            let plistPath = "\(appPath)/Info.plist"

            guard let plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { continue }

            guard let bundleId = plist["CFBundleIdentifier"] as? String else { continue }

            // Tenta obter o nome do ícone
            var iconPath: String = ""

            if let iconsDict = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any],
               let iconFiles = iconsDict["CFBundleIconFiles"] as? [String] {
                if let iconName = iconFiles.last {
                    let iconsPath = [
                        appPath+"/"+iconName+".png",
                        appPath+"/"+iconName+"@2x.png",
                        appPath+"/"+iconName+"@3x.png",
                        appPath+"/"+iconName
                    ]
                    for path in iconsPath {
                        if fileManager.fileExists(atPath: path) {
                            iconPath = path
                            break
                        }
                    }
                }
            }
            
            var plistFiles: [String] = []

            if let fileEnum = fileManager.enumerator(atPath: appPath) {
                for case let File as String in fileEnum {
                    if File.hasSuffix(".plist") {
                        plistFiles.append(appPath+"/"+File)
                    }
                }
            }


            let appInfo = AppInfo(
                name: name,
                caminho: appPath,
                icone: iconPath,
                plists: plistFiles
            )

            result[bundleId] = appInfo
        }

        return result
    }
}
