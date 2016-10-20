import UIKit
import CameraKitUI


class BaseCameraViewController: CameraViewController {
    @IBAction
    func closeButtonPressed(_ sender: UIButton!) {
        dismiss(animated: true, completion: nil)
    }
}
