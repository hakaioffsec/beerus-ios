import Foundation


class AppManager {
    struct AppInfo {
        let name: String
        let caminho: String
        let icone: String
        let plists: [String]
        let dataContainer: String
    }

    private func getDataContainerURLs() -> [String: String] {
        var containers: [String: String] = [:]

        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = workspaceClass.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue(),
              let apps = workspace.perform(NSSelectorFromString("allInstalledApplications"))?.takeUnretainedValue() as? [NSObject]
        else {
            return containers
        }

        for app in apps {
            guard let bundleId = app.perform(NSSelectorFromString("bundleIdentifier"))?.takeUnretainedValue() as? String,
                  let dataURL = app.perform(NSSelectorFromString("dataContainerURL"))?.takeUnretainedValue() as? URL
            else { continue }

            containers[bundleId] = dataURL.path
        }

        return containers
    }

    func getApps() -> [String: AppInfo] {
        let appDirectory = "/private/var/containers/Bundle/Application/"
        let fileManager = FileManager.default
        var result: [String: AppInfo] = [:]
        let dataContainers = getDataContainerURLs()

        guard let appUUIDs = try? fileManager.contentsOfDirectory(atPath: appDirectory) else {
            print("Failed to access app directory.")
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
                plists: plistFiles,
                dataContainer: dataContainers[bundleId] ?? ""
            )

            result[bundleId] = appInfo
        }

        return result
    }
}
