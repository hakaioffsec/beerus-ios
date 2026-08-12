import UIKit

final class Alert {

    static func show(title: String = "", message: String = "") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default, handler: nil)
        
        alert.addAction(action)
        
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                if let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(alert, animated: true, completion: nil)
                }
            }
        }
    }
    
    static func showInput(
        title: String = "",
        message: String = "",
        placeholder: String = "",
        keyboardType: UIKeyboardType = .default,
        completion: @escaping (_ value: String?) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = placeholder
            textField.keyboardType = keyboardType
        }

        // Cancelar
        let actionCancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(nil)
        }

        // Confirmar
        let actionConfirm = UIAlertAction(title: "OK", style: .default) { _ in
            let text = alert.textFields?.first?.text
            completion(text)
        }

        alert.addAction(actionCancel)
        alert.addAction(actionConfirm)

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            }
        }
    }


    static func showMultipleInput(
        title: String = "",
        message: String = "",
        inputs: [(name: String, placeholder: String)],
        keyboardType: UIKeyboardType = .default,
        completion: @escaping (_ values: [String: String]?) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        for input in inputs {
            alert.addTextField { textField in
                textField.placeholder = input.placeholder
                textField.keyboardType = keyboardType
            }
        }

        let actionCancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(nil)
        }

        let actionConfirm = UIAlertAction(title: "OK", style: .default) { _ in
            var result: [String: String] = [:]

            if let textFields = alert.textFields {
                for (index, field) in textFields.enumerated() {
                    let key = inputs[index].name
                    result[key] = field.text ?? ""
                }
            }

            completion(result)
        }

        alert.addAction(actionCancel)
        alert.addAction(actionConfirm)

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            }
        }
    }
}

// MARK: - UIViewController Extension

extension UIViewController {

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
