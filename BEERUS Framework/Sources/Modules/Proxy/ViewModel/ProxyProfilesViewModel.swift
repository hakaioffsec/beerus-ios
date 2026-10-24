import Foundation

final class ProxyProfilesViewModel {

    weak var coordinator: ProxyProfilesCoordinator?

    private let storage: ProxyProfilesStorage
    private(set) var profiles: [ProxyProfile] = []

    var onProfilesChanged: ([ProxyProfile]) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    init(storage: ProxyProfilesStorage = .shared) {
        self.storage = storage
    }

    func viewDidLoad() {
        reload()
    }

    func tappedAddProfile() {
        coordinator?.presentAddProfile { [weak self] name, proxy in
            self?.addProfile(name: name, proxy: proxy)
        }
    }

    func addProfile(name: String, proxy: String) {
        if storage.addProfile(name: name, proxy: proxy) {
            reload()
        } else {
            onError("Não foi possível salvar o perfil. Verifique se o nome já existe.")
        }
    }

    func toggle(at index: Int, isOn: Bool) {
        guard profiles.indices.contains(index) else { return }

        let profile = profiles[index]
        let result = RootExec.setProxy(isOn ? profile.proxy : "OFF")

        guard result.exitCode == 0 else {
            onError("Não foi possível aplicar o proxy.")
            onProfilesChanged(profiles)
            return
        }

        storage.setProfileEnabled(named: profile.name, enabled: isOn)
        reload()
    }

    func delete(at index: Int) {
        guard profiles.indices.contains(index) else { return }

        let profile = profiles[index]

        if profile.isEnabled {
            _ = RootExec.setProxy("OFF")
        }

        storage.deleteProfile(named: profile.name)
        reload()
    }

    private func reload() {
        profiles = storage.fetchProfiles()
        onProfilesChanged(profiles)
    }
}
