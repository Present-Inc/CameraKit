import UIKit
import CameraKit


class StillImageCameraViewController: BaseCameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.photo] }
    
    override func cameraController(_ controller: CameraController, didOutputImage image: UIImage) {
        saveImageToCameraRoll(image)
    }
    
    func saveImageToCameraRoll(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(StillImageCameraViewController.successfullySavedImage(_:error:context:)), nil)
    }
    
    func successfullySavedImage(_ image: UIImage, error: NSError, context: UnsafeMutableRawPointer) {
        print("Successfully saved image!")
    }
}
