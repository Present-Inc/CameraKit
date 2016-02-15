import UIKit
import CameraKit


class SquareCameraViewController: CameraViewController {
    override func cameraController(controller: CameraController, didOutputImage image: UIImage) {
        processImage(image)
    }
    
    private func processImage(image: UIImage) {
        guard let cgImage = image.CGImage
        else {
            fatalError("Could not extract CGImage from UIImage")
        }
        
        var imageHeight = image.size.height
        var imageWidth = image.size.width
        
        if imageHeight > imageWidth {
            imageHeight = imageWidth
        } else {
            imageWidth = imageHeight
        }
        
        let size = CGSize(width: imageWidth, height: imageHeight)
        
        let referenceSize: (width: CGFloat, height: CGFloat) = (CGFloat(CGImageGetWidth(cgImage)), CGFloat(CGImageGetHeight(cgImage)))
        
        let x = (referenceSize.width - size.width) / 2
        let y = (referenceSize.height - size.height) / 2
        
        let cropRect = CGRectMake(x, y, size.width, size.height)
        guard let imageRef = CGImageCreateWithImageInRect(cgImage, cropRect)
        else {
            fatalError("Could not create image in rect")
        }
        
        let croppedImage = UIImage(CGImage: imageRef, scale: 0, orientation: image.imageOrientation)
        
        saveImageToCameraRoll(croppedImage)
    }
}