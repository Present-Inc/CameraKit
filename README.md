# CameraKit
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)  
The easiest way to get camera frames showing up on screen. Written in Swift.

### TODO
- [x] Carthage Support
- [ ] OSX Target
- [x] Usage examples
- [ ] CocoaPods Support
- [x] Still Image Capture
- [ ] Event handling beyond notification center

### Features

### Usage

Import CameraKit

```Swift
import CameraKit
```

#### Setting up the camera

The easiest way to start getting camera input to appear on the screen is by using the convenience initializer.
```Swift
  // Instantiate a CameraKit.CameraController with a view for convenience
  cameraController = CameraController(view: cameraPreview)
  cameraController.delegate = self
```

Otherwise, you can add the preview layer as a sublayer to your view.
```Swift
  cameraController = CameraController()
  cameraController.delegate = self
  
  cameraController.previewLayer.frame = self.cameraPreview.bounds
  self.cameraPreview.layer.addSublayer(cameraController.previewLayer)

```
Call `startCaptureSession()` and `stopCaptureSession()` to start and stop capture

```Swift
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
        
    cameraController.startCaptureSession()
  }
    
  override func viewDidDisappear(animated: Bool) {
    super.viewDidDisappear(animated)
        
    cameraController.stopCaptureSession()
  }
```

When the capture session starts running, `CMSampleBufferRef`'s will begin flowing through the delegate method.  
`cameraController(_:_:_:)` is called on an arbitrary background thread, dependent on the `type`. It is the user's responsibility to ensure any UI updates happen on the main thread.
```Swift
extension ViewController: CameraControllerDelegate {
  func cameraController(controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, type: CameraController.FrameType) {
    // Process video frames here
  }
}
```

#### Toggle the camera

```Swift
cameraController.toggleCameraPosition()
```

#### Toggle the LED
```Swift
cameraController.toggleLED()
```

#### Set the zoom
```Swift
// Accepts a number between 1.0 and 8.0
cameraController.setZoom(_)
```

#### Set the focus mode
```Swift
let touchPoint = gestureRecognizer.locationInView(cameraPreview)

cameraController.setFocusMode(.AutoFocus, atPoint: touchPoint)
```

#### Set the exposure mode
```Swift
let touchPoint = gestureRecognizer.locationInView(cameraPreview)

cameraController.setExposureMode(.AutoExposure, atPoint: touchPoint)
```

#### Set the white balance
```Swift
cameraController.setWhiteBalanceMode(.Locked)
```

#### Set low light boost
```Swift
// Enable
cameraController.setLowLightBoost()

// Disable
cameraController.setLowLightBoost(false)
```

## Installation

`CameraKit` is available for installation using your favorite Xcode dependency manager, or by adding the `.swift` files to your project directly.

### Carthage
To integrate `CameraKit` using [Carthage](http://github.com/Carthage/Carthage/), just add the following to your Cartfile:
```
github "Present-Inc/CameraKit"
```

### CocoaPods: Coming Soon
~~`CameraKit` is available for installation using [CocoaPods](http://cocoapods.org/).~~

~~To integrate, just add the following line to your `Podfile`:~~

```ruby
pod 'CameraKit'
```
