import UIKit

final class AppDetailViewController: BaseViewController {

    var viewModel: AppDetailViewModel!

    private let rootView = AppDetailView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        rootView.versionsButton.addTarget(self, action: #selector(versionsTapped), for: .touchUpInside)
        rootView.configure(
            name: viewModel.nameText,
            bundle: viewModel.bundleText,
            version: viewModel.versionText,
            id: viewModel.idText
        )
    }
}

private extension AppDetailViewController {
    @objc func downloadTapped() {
        viewModel.tappedDownload()
    }

    @objc func versionsTapped() {
        viewModel.tappedVersions()
    }
}
