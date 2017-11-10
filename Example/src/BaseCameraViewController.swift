import UIKit
import CameraKit


class BaseCameraViewController: CameraViewController {
    @IBAction
    func closeButtonPressed(_ sender: UIButton!) {
        dismiss(animated: true, completion: nil)
    }
}
