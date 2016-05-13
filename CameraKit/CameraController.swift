import UIKit
import CoreGraphics

let CameraKitDomain = "tv.present.CameraKit"
private let VideoOutputQueueIdentifier = CameraKitDomain + ".videoQueue"
private let AudioOutputQueueIdentifier = CameraKitDomain + ".audioQueue"

private let MaxZoomFactor: CGFloat = 8.0

public protocol CameraControllerDelegate {
    func cameraController(controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, type: CameraController.FrameType)
    func cameraController(controller: CameraController, didOutputImage image: UIImage)
}

public class CameraController: NSObject {
    public enum FrameType {
        case Audio
        case Video
    }
    
    public enum CaptureMode {
        case Video
        case SlowMotionVideo
        case Photo
    }
    
    public enum Error: ErrorType {
        case InvalidStillImageOutputConnection
        
        case VideoModeNotEnabled
        case PhotoModeNotEnabled
        case AudioCaptureNotEnabled
        
        case NoVideoDevice
        case NoAudioDevice
        
        case CouldNotLockVideoDevice
        
        case NoSuitableFormatForSlowMotion
    
        // TODO: This should be expanded upon to provide specific errors for each point where AVFoundation can fail
        case AVFoundationError(NSError)
    }
    
    public var delegate: CameraControllerDelegate?
    
    public let captureSession: AVCaptureSession = AVCaptureSession()
    public let previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer()
    
    private let captureModes: Set<CaptureMode>
    
    private var paused: Bool = false
    private var configuringCaptureSession: Bool = false
    
    private var frontCameraDevice: AVCaptureDevice?
    private var backCameraDevice: AVCaptureDevice?
    
    private var frontCameraDeviceInput: AVCaptureDeviceInput?
    private var backCameraDeviceInput: AVCaptureDeviceInput?
    
    // Capture session inputs
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    
    // Capture session output
    private var videoDeviceOutput: AVCaptureVideoDataOutput?
    private var audioDeviceOutput: AVCaptureAudioDataOutput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    
    // Capture session connections
    private var videoConnection: AVCaptureConnection?
    private var audioConnection: AVCaptureConnection?
    
    // Used as the callback queue for the AVCaptureVideoDataOutput
    private let videoOutputQueue: dispatch_queue_t = dispatch_queue_create(VideoOutputQueueIdentifier, DISPATCH_QUEUE_SERIAL)
    // Used as the callback queue for the AVCaptureAudioDataOutput
    private let audioOutputQueue: dispatch_queue_t = dispatch_queue_create(AudioOutputQueueIdentifier, DISPATCH_QUEUE_SERIAL)
    
    deinit {
        teardownCaptureSession()
    }
    
    public init(captureModes: Set<CaptureMode>) throws {
        self.captureModes = captureModes
        
        super.init()
        
        try setup()
    }
    
    public convenience init(captureMode: CaptureMode) throws {
        try self.init(captureModes: [captureMode])
    }
    
    public convenience init(view: UIView, captureModes: Set<CaptureMode> = [.Video]) throws {
        try self.init(captureModes: captureModes)
        
        let rootLayer = view.layer
        rootLayer.masksToBounds = true
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
    }
    
    public func startCaptureSession() {
        if !captureSession.running {
            self.captureSession.startRunning()
        }
    }
    
    public func stopCaptureSession() {
        if captureSession.running {
            self.captureSession.stopRunning()
        }
    }
    
    public func configureAudioSession(category: String, options: AVAudioSessionCategoryOptions) throws {
        if !videoModeEnabled {
            throw Error.AudioCaptureNotEnabled
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(category, withOptions: options)
            try audioSession.setActive(true)
        } catch let error as NSError {
            throw Error.AVFoundationError(error)
        }
    }
    
    public func captureStillImage() throws {
        if !photoModeEnabled {
            throw Error.PhotoModeNotEnabled
        }
        
        if let videoConnection = stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo) where (videoConnection.enabled && videoConnection.active) {
            stillImageOutput?.captureStillImageAsynchronouslyFromConnection(videoConnection, completionHandler: { [unowned self] sampleBuffer, error in
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
                guard let image = UIImage(data: imageData)
                else {
                    return
                }
                
                self.delegate?.cameraController(self, didOutputImage: image)
            })
        } else {
            throw Error.InvalidStillImageOutputConnection
        }
    }
    
    private func setSlowMotion() throws {
        guard let videoDevice = backCameraDevice
        else {
            throw Error.NoVideoDevice
        }
        
        let deviceFormats = videoDevice.formats as? [AVCaptureDeviceFormat] ?? []
        
        var bestFormat: AVCaptureDeviceFormat?
        var bestFrameRateRange: AVFrameRateRange!
        
        for format in deviceFormats {
            guard let frameRateRanges = format.videoSupportedFrameRateRanges as? [AVFrameRateRange]
            else {
                continue
            }
            
            for range in frameRateRanges {
                guard let frameRateRange = bestFrameRateRange
                else {
                    bestFormat = format
                    bestFrameRateRange = range
                    continue
                }
                
                if range.maxFrameRate > frameRateRange.maxFrameRate {
                    bestFormat = format
                    bestFrameRateRange = range
                }
            }
        }
        
        if let bestFormat = bestFormat {
            try lockVideoDevice(videoDevice) {
                $0.activeFormat = bestFormat
                $0.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration
                $0.activeVideoMaxFrameDuration = bestFrameRateRange.maxFrameDuration
            }
            
//            let formatDescription = bestFormat.formatDescription
//            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
//            
//            print("Configured for \(dimensions.width)x\(dimensions.height) at \(bestFrameRateRange.maxFrameRate)")
        } else {
            throw Error.NoSuitableFormatForSlowMotion
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        if configuringCaptureSession {
            return
        }
        
        if connection == videoConnection {
            delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, type: .Video)
        } else if connection == audioConnection {
            delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, type: .Audio)
        }
    }
}

// MARK: - Camera Methods

public extension CameraController {
    private func lockVideoDevice(videoDevice: AVCaptureDevice, configure: AVCaptureDevice -> Void) throws {
        do {
            try videoDevice.lockForConfiguration()
            configure(videoDevice)
            videoDevice.unlockForConfiguration()
        } catch {
            throw Error.CouldNotLockVideoDevice
        }
    }
    
    // MARK: Focus
    /// TODO: Support setting the focus mode with point defaulting to previewLayer.center
    func setFocusMode(focusMode: AVCaptureFocusMode, atPoint point: CGPoint) throws {
        let focusPoint = previewLayer.captureDevicePointOfInterestForPoint(point)
        guard let videoDevice = currentVideoDevice
        else {
            throw Error.NoVideoDevice
        }
        
        if videoDevice.focusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
            try lockVideoDevice(videoDevice) {
                $0.focusPointOfInterest = focusPoint
                $0.focusMode = focusMode
            }
        }
    }
    
    // MARK: Exposure
    /// TODO: Support setting the exposure mode with point defaulting to previewLayer.center
    func setExposureMode(exposureMode: AVCaptureExposureMode, atPoint point: CGPoint) throws {
        let exposurePoint = previewLayer.captureDevicePointOfInterestForPoint(point)
        
        if let videoDevice = currentVideoDevice {
            if videoDevice.exposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                try lockVideoDevice(videoDevice) {
                	$0.exposurePointOfInterest = exposurePoint
                    $0.exposureMode = exposureMode
                }
            }
        }
    }
    
    // MARK: White Balance
    func setWhiteBalanceMode(whiteBalanceMode: AVCaptureWhiteBalanceMode) throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.isWhiteBalanceModeSupported(whiteBalanceMode) {
                try lockVideoDevice(videoDevice) {
                    $0.whiteBalanceMode = whiteBalanceMode
                }
            }
        }
    }
    
    // MARK: Low Light Boost
    func setLowLightBoost(automaticallyEnabled: Bool = true) throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.lowLightBoostSupported {
                try lockVideoDevice(videoDevice) {
                    $0.automaticallyEnablesLowLightBoostWhenAvailable = automaticallyEnabled
                }
            }
        }
    }
    
    // MARK: Torch
    func setTorchMode(mode: AVCaptureTorchMode) throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.hasTorch && videoDevice.torchAvailable {
                try lockVideoDevice(videoDevice) {
                    $0.torchMode = mode
                }
            }
        }
    }
    
    func toggleLED() throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.hasTorch && videoDevice.torchAvailable {
                try lockVideoDevice(videoDevice) { videoDevice in
                    switch(videoDevice.torchMode) {
                    case .Off:
                        videoDevice.torchMode = .On
                    case .On:
                        videoDevice.torchMode = .Off
                    default:
                        break
                    }
                }
            }
        }
    }
    
    // MARK: Zoom
    func setZoom(zoomLevel: CGFloat) throws -> Bool {
        if let videoDevice = currentVideoDevice {
            if zoomLevel <= MaxZoomFactor && zoomLevel >= 1 {
                try lockVideoDevice(videoDevice) {
                    $0.videoZoomFactor = zoomLevel
                }

                return true
            }
        }
        
        return false
    }
    
    // MARK: Camera Position
    
    /// Convenience method for toggling the camera position.
    func toggleCameraPosition() -> Bool {
        guard let cameraPosition = currentVideoDevice?.position
        else {
            return false
        }
        
        return cameraPosition == .Back ? setCamera(.Front) : setCamera(.Back)
    }
    
    private func setCamera(position: AVCaptureDevicePosition) -> Bool {
        if slowMotionEnabled && position != .Back {
            return false
        }
        
        let deviceInput = position == .Front ? frontCameraDeviceInput : backCameraDeviceInput
        
        if let deviceInput = deviceInput {
            configureCaptureSession { captureSession in
                self.replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput)
            }
            
            return true
        }
        
        return false
    }
    
    func addInput(input: AVCaptureInput?) {
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
    }
    
    func addOutput(output: AVCaptureOutput?) {
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
    }
    
    func configureCaptureSession(closure: (AVCaptureSession) -> ()) {
        configuringCaptureSession = true
    
        stopCaptureSession()
        
        captureSession.beginConfiguration()
        closure(captureSession)
        captureSession.commitConfiguration()
        
        startCaptureSession()
        
        configuringCaptureSession = false
    }
}

// MARK: - Setup Methods

private extension CameraController {
    func setup() throws {
        try setupCaptureSession()
        setupPreviewLayer()
    }
    
    func setupPreviewLayer() {
        previewLayer.session = captureSession
        previewLayer.videoGravity = AVVideoScalingModeFit
        previewLayer.connection.videoOrientation = .Portrait
    }
    
    func setupCaptureSession() throws {
        /// TODO: Allow this to be input by the user
        if captureModes.count == 1 && photoModeEnabled {
            captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        } else {
            captureSession.sessionPreset = AVCaptureSessionPresetHigh
        }
        
        try self.setupVideoDevices()
        try setupVideoDeviceInput()
        setupVideoDeviceOutput()
        setupVideoConnection()
        
        if !photoModeEnabled {
            try setupAudioDeviceInput()
            setupAudioDeviceOutput()
            setupAudioConnection()
        } else {
            setupStillImageOutput()
        }
        
        if slowMotionEnabled {
            try setSlowMotion()
        }
    }
}

// MARK: - Capture Session Utilities

private extension CameraController {
    func setupVideoDevices() throws {
        frontCameraDevice = videoDeviceForPosition(.Front)
        backCameraDevice = videoDeviceForPosition(.Back)
        
        do {
            frontCameraDeviceInput = try AVCaptureDeviceInput(device: frontCameraDevice)
            backCameraDeviceInput = try AVCaptureDeviceInput(device: backCameraDevice)
        } catch let error as NSError {
            throw Error.AVFoundationError(error)
        }
    }
    
    func setupVideoDeviceInput() throws {
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: CameraController.defaultVideoDevice)
            addInput(videoDeviceInput)
        } catch let error as NSError {
            throw Error.AVFoundationError(error)
        }
    }
    
    func setupAudioDeviceInput() throws {
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
        }
        
        do {
            audioDeviceInput = try AVCaptureDeviceInput(device: CameraController.defaultAudioDevice)
            addInput(audioDeviceInput)
        } catch let error as NSError {
            throw Error.AVFoundationError(error)
        }
    }
    
    func setupVideoDeviceOutput() {
        // If there's already a `videoDeviceOutput`, remove it
        if let videoOutput = videoDeviceOutput {
            captureSession.removeOutput(videoOutput)
        }
        
        // Setup the video device output
        videoDeviceOutput = AVCaptureVideoDataOutput()
        videoDeviceOutput?.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoDeviceOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey: NSNumber(unsignedInt: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        
        // Add the video device output
        addOutput(videoDeviceOutput)
    }
    
    func setupAudioDeviceOutput() {
        // If there's already an `audioDeviceOutput`, remove it
        if let audioOutput = audioDeviceOutput {
            captureSession.removeOutput(audioOutput)
        }
        
        // Setup the audio device output
        audioDeviceOutput = AVCaptureAudioDataOutput()
        audioDeviceOutput?.setSampleBufferDelegate(self, queue: audioOutputQueue)
        
        // Add the audio device output
        addOutput(audioDeviceOutput)
    }
    
    func setupStillImageOutput() {
        if let _ = stillImageOutput {
            return
        }
        
        stillImageOutput = AVCaptureStillImageOutput()
        
        stillImageOutput?.outputSettings = [
            AVVideoCodecKey: AVVideoCodecJPEG
        ]
        
        addOutput(stillImageOutput)
    }
    
    func setupVideoConnection() {
        // Setup the video connction
        videoConnection = videoDeviceOutput?.connectionWithMediaType(AVMediaTypeVideo)
        
        // TODO: Support different video orientations
        videoConnection?.videoOrientation = .Portrait
        videoConnection?.preferredVideoStabilizationMode = .Auto
    }
    
    func setupAudioConnection() {
        // Setup the audio connection
        audioConnection = audioDeviceOutput?.connectionWithMediaType(AVMediaTypeAudio)
    }
    
    func teardownCaptureSession() {
        for input in inputDevices {
            captureSession.removeInput(input)
        }
        
        for output in outputDevices {
            captureSession.removeOutput(output)
        }
        
        previewLayer.removeFromSuperlayer()
        previewLayer.session = nil
    }
}

// MARK: - Computed Properties

private extension CameraController {
    var photoModeEnabled: Bool {
        return captureModes.contains(.Photo)
    }
    
    var videoModeEnabled: Bool {
        return captureModes.contains(.Video)
    }
    
    var slowMotionEnabled: Bool {
        return captureModes.contains(.SlowMotionVideo)
    }
}

// MARK: AVFoundation Utilities

public extension CameraController {
    public static var videoDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice]
    }
    
    public static var audioDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio) as! [AVCaptureDevice]
    }
    
    public static var defaultAudioDevice: AVCaptureDevice {
        return AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
    }
    
    public static var defaultVideoDevice: AVCaptureDevice {
        return AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
    }
    
    public var inputDevices: [AVCaptureDeviceInput] {
        return captureSession.inputs as! [AVCaptureDeviceInput]
    }
    
    public var outputDevices: [AVCaptureOutput] {
        return captureSession.outputs as! [AVCaptureOutput]
    }
    
    public var currentAudioDeviceInput: AVCaptureDeviceInput? {
        return currentInputDeviceForMediaType(AVMediaTypeAudio)
    }
    
    public var currentVideoDeviceInput: AVCaptureDeviceInput? {
        return currentInputDeviceForMediaType(AVMediaTypeVideo)
    }
    
    public var currentVideoDevice: AVCaptureDevice? {
        return videoDeviceInput?.device
    }
    
    public var currentAudioDevice: AVCaptureDevice? {
        return audioDeviceInput?.device
    }
    
    func currentInputDeviceForMediaType(mediaType: String) -> AVCaptureDeviceInput? {
        return inputDevices
            .filter { $0.device.hasMediaType(mediaType) }
            .first
    }
    
    func videoDeviceForPosition(position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        return CameraController.videoDevices.filter { $0.position == position }.first
    }
    
    private func replaceCurrentVideoDeviceWithDevice(device: AVCaptureDevice) throws {
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput)
        } catch let error as NSError {
            throw Error.AVFoundationError(error)
        }
    }
    
    private func replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput: AVCaptureDeviceInput) {
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
        }
        
        videoDeviceInput = deviceInput
        addInput(deviceInput)
        
        setupVideoDeviceOutput()
        setupVideoConnection()
    }
    
    private func replaceCurrentAudioDeviceWithDevice(device: AVCaptureDevice) throws {
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            replaceCurrentAudioDeviceInputWithDeviceInput(deviceInput)
        } catch let error as NSError {
            throw Error.AVFoundationError(error)
        }
    }
    
    private func replaceCurrentAudioDeviceInputWithDeviceInput(deviceInput: AVCaptureDeviceInput) {
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
        }
        
        audioDeviceInput = deviceInput
        addInput(deviceInput)
        
        setupAudioDeviceOutput()
        setupAudioConnection()
    }
    
}
