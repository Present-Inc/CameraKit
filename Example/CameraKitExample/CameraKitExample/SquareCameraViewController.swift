import UIKit
import CameraKit


class SquareCameraViewController: StillImageCameraViewController {
    override func cameraController(controller: CameraController, didOutputImage image: UIImage) {
        processImage(image)
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    private func processImage(image: UIImage) {
        let inputSize = image.size
        let outputSideLength: CGFloat = 1024.0
        let outputSize = CGSize(width: outputSideLength, height: outputSideLength)
        let scale = max(outputSideLength / inputSize.width, outputSideLength / inputSize.height)
        let scaledInputSize = CGSizeMake(inputSize.width * scale, inputSize.height * scale)
        /// TODO: Figure out the real center by overlaying the `cameraMask` over the preview layer
        let center = CGPoint(x: outputSize.width / 2, y: outputSize.height / 2)
        let outputRect = CGRect(
            x: center.x - scaledInputSize.width / 2.0,
            y: center.y - scaledInputSize.height / 2.0,
            width: scaledInputSize.width,
            height: scaledInputSize.height
        )
        
        UIGraphicsBeginImageContextWithOptions(outputSize, true, 0)
        
        image.drawInRect(outputRect)
        
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        saveImageToCameraRoll(scaledImage)
    }
}