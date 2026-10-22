import Foundation

protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get }
    func start()
}
