import UIKit

final class HomeViewController: BaseViewController {

    private let rootView = HomeView()

    override func loadView() {
        view = rootView
    }
}
