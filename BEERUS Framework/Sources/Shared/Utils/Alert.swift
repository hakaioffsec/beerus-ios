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

        // Campo de texto
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


}
