import UIKit
import CoreGraphics
import AVFoundation

let CameraKitDomain = "tv.present.CameraKit"
private let VideoOutputQueueIdentifier = CameraKitDomain + ".videoQueue"
private let AudioOutputQueueIdentifier = CameraKitDomain + ".audioQueue"

private let MaxZoomFactor: CGFloat = 8.0

public protocol CameraControllerDelegate: class {
    func cameraController(_ controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, type: CameraController.FrameType)
    func cameraController(_ controller: CameraController, didOutputImage image: UIImage)
}

open class CameraController: NSObject {
    public enum FrameType {
        case audio
        case video
    }
    
    public enum CaptureMode {
        case video
        case slowMotionVideo
        case photo
    }
    
    public enum Error: Swift.Error {
        case simulator
        
        case invalidStillImageOutputConnection
        
        case videoModeNotEnabled
        case photoModeNotEnabled
        case audioCaptureNotEnabled
        
        case noVideoDevice
        case noAudioDevice
        
        case couldNotLockVideoDevice
        
        case noSuitableFormatForSlowMotion
    
        // TODO: This should be expanded upon to provide specific errors for each point where AVFoundation can fail
        case avFoundationError(NSError)
    }
    
    open weak var delegate: CameraControllerDelegate?
    
    @objc open let captureSession: AVCaptureSession = AVCaptureSession()
    @objc open let previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer()
    
    fileprivate let captureModes: Set<CaptureMode>
    
    fileprivate var paused: Bool = false
    fileprivate var configuringCaptureSession: Bool = false
    
    fileprivate var frontCameraDevice: AVCaptureDevice?
    fileprivate var backCameraDevice: AVCaptureDevice?
    
    fileprivate var frontCameraDeviceInput: AVCaptureDeviceInput?
    fileprivate var backCameraDeviceInput: AVCaptureDeviceInput?
    
    // Capture session inputs
    fileprivate var videoDeviceInput: AVCaptureDeviceInput?
    fileprivate var audioDeviceInput: AVCaptureDeviceInput?
    
    // Capture session output
    fileprivate var videoDeviceOutput: AVCaptureVideoDataOutput?
    fileprivate var audioDeviceOutput: AVCaptureAudioDataOutput?
    fileprivate var stillImageOutput: AVCaptureStillImageOutput?
    
    // Capture session connections
    fileprivate var videoConnection: AVCaptureConnection?
    fileprivate var audioConnection: AVCaptureConnection?
    
    // Used as the callback queue for the AVCaptureVideoDataOutput
    fileprivate let videoOutputQueue: DispatchQueue = DispatchQueue(label: VideoOutputQueueIdentifier, attributes: [])
    // Used as the callback queue for the AVCaptureAudioDataOutput
    fileprivate let audioOutputQueue: DispatchQueue = DispatchQueue(label: AudioOutputQueueIdentifier, attributes: [])
    
    deinit {
        teardownCaptureSession()
    }
    
    public init(captureModes: Set<CaptureMode>) throws {
        self.captureModes = captureModes
        
        super.init()
        
        try setup()
    }
    
    public convenience init(captureMode: CaptureMode = .video) throws {
        try self.init(captureModes: [captureMode])
    }
    
    @objc open func startCaptureSession() {
        if !captureSession.isRunning {
            self.captureSession.startRunning()
        }
    }
    
    @objc open func stopCaptureSession() {
        if captureSession.isRunning {
            self.captureSession.stopRunning()
        }
    }
    
    @objc open func configureAudioSession(_ category: String, options: AVAudioSessionCategoryOptions) throws {
        if !videoModeEnabled {
            throw Error.audioCaptureNotEnabled
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(category, with: options)
            try audioSession.setActive(true)
        } catch let error as NSError {
            throw Error.avFoundationError(error)
        }
    }
    
    @objc open func captureStillImage() throws {
        if !photoModeEnabled {
            throw Error.photoModeNotEnabled
        }
        
        if let videoConnection = stillImageOutput?.connection(with: AVMediaType.video) , (videoConnection.isEnabled && videoConnection.isActive) {
            stillImageOutput?.captureStillImageAsynchronously(from: videoConnection, completionHandler: { [unowned self] sampleBuffer, error in
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer!)
                guard let image = UIImage(data: imageData!)
                else {
                    return
                }
                
                self.delegate?.cameraController(self, didOutputImage: image)
            })
        } else {
            throw Error.invalidStillImageOutputConnection
        }
    }
    
    fileprivate func setSlowMotion() throws {
        guard let videoDevice = backCameraDevice
        else {
            throw Error.noVideoDevice
        }
        
        let deviceFormats = videoDevice.formats
        
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRateRange: AVFrameRateRange?
        
        for format in deviceFormats {
            let frameRateRanges = format.videoSupportedFrameRateRanges
            if frameRateRanges.isEmpty {
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
        
        if let bestFormat = bestFormat,
            let bestFrameRateRange = bestFrameRateRange {
            try lockVideoDevice(videoDevice) {
                $0.activeFormat = bestFormat
                $0.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration
                $0.activeVideoMaxFrameDuration = bestFrameRateRange.maxFrameDuration
            }
        } else {
            throw Error.noSuitableFormatForSlowMotion
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ captureOutput: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if configuringCaptureSession {
            return
        }
        
        if connection == videoConnection {
            delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, type: .video)
        } else if connection == audioConnection {
            delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, type: .audio)
        }
    }
}

// MARK: - Camera Methods

public extension CameraController {
    fileprivate func lockVideoDevice(_ videoDevice: AVCaptureDevice, configure: (AVCaptureDevice) -> Void) throws {
        do {
            try videoDevice.lockForConfiguration()
            configure(videoDevice)
            videoDevice.unlockForConfiguration()
        } catch {
            throw Error.couldNotLockVideoDevice
        }
    }
    
    // MARK: Focus
    /// TODO: Support setting the focus mode with point defaulting to previewLayer.center
    @objc func setFocusMode(_ focusMode: AVCaptureDevice.FocusMode, atPoint point: CGPoint) throws {
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        guard let videoDevice = currentVideoDevice
        else {
            throw Error.noVideoDevice
        }
        
        if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
            try lockVideoDevice(videoDevice) {
                $0.focusPointOfInterest = focusPoint
                $0.focusMode = focusMode
            }
        }
    }
    
    // MARK: Exposure
    /// TODO: Support setting the exposure mode with point defaulting to previewLayer.center
    @objc func setExposureMode(_ exposureMode: AVCaptureDevice.ExposureMode, atPoint point: CGPoint) throws {
        let exposurePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        
        if let videoDevice = currentVideoDevice {
            if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                try lockVideoDevice(videoDevice) {
                	$0.exposurePointOfInterest = exposurePoint
                    $0.exposureMode = exposureMode
                }
            }
        }
    }
    
    // MARK: White Balance
    @objc func setWhiteBalanceMode(_ whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode) throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.isWhiteBalanceModeSupported(whiteBalanceMode) {
                try lockVideoDevice(videoDevice) {
                    $0.whiteBalanceMode = whiteBalanceMode
                }
            }
        }
    }
    
    // MARK: Low Light Boost
    @objc func setLowLightBoost(_ automaticallyEnabled: Bool = true) throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.isLowLightBoostSupported {
                try lockVideoDevice(videoDevice) {
                    $0.automaticallyEnablesLowLightBoostWhenAvailable = automaticallyEnabled
                }
            }
        }
    }
    
    // MARK: Torch
    @objc func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.hasTorch && videoDevice.isTorchAvailable {
                try lockVideoDevice(videoDevice) {
                    $0.torchMode = mode
                }
            }
        }
    }
    
    @objc func toggleLED() throws {
        if let videoDevice = currentVideoDevice {
            if videoDevice.hasTorch && videoDevice.isTorchAvailable {
                try lockVideoDevice(videoDevice) { videoDevice in
                    switch(videoDevice.torchMode) {
                    case .off:
                        videoDevice.torchMode = .on
                    case .on:
                        videoDevice.torchMode = .off
                    default:
                        break
                    }
                }
            }
        }
    }
    
    // MARK: Zoom
    func setZoom(_ zoomLevel: CGFloat) throws -> Bool {
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
    @objc func toggleCameraPosition() -> Bool {
        guard let cameraPosition = currentVideoDevice?.position
        else {
            return false
        }
        
        return cameraPosition == .back ? setCamera(.front) : setCamera(.back)
    }
    
    fileprivate func setCamera(_ position: AVCaptureDevice.Position) -> Bool {
        if slowMotionEnabled && position != .back {
            return false
        }
        
        let deviceInput = position == .front ? frontCameraDeviceInput : backCameraDeviceInput
        
        if let deviceInput = deviceInput {
            configureCaptureSession { captureSession in
                self.replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput)
            }
            
            return true
        }
        
        return false
    }
    
    @objc func addInput(_ input: AVCaptureInput?) {
        if captureSession.canAddInput(input!) {
            captureSession.addInput(input!)
        }
    }
    
    @objc func addOutput(_ output: AVCaptureOutput?) {
        if captureSession.canAddOutput(output!) {
            captureSession.addOutput(output!)
        }
    }
    
    @objc func configureCaptureSession(_ closure: (AVCaptureSession) -> ()) {
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
        previewLayer.videoGravity = AVLayerVideoGravity(rawValue: AVVideoScalingModeFit)
        previewLayer.connection?.videoOrientation = .portrait
    }
    
    func setupCaptureSession() throws {
        #if arch(x86_64) || arch(i386)
            throw Error.simulator
        #endif
        
        /// TODO: Allow this to be input by the user
        if captureModes.count == 1 && photoModeEnabled {
            captureSession.sessionPreset = AVCaptureSession.Preset.photo
        } else {
            captureSession.sessionPreset = AVCaptureSession.Preset.high
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
        frontCameraDevice = videoDeviceForPosition(.front)
        backCameraDevice = videoDeviceForPosition(.back)
        
        do {
            frontCameraDeviceInput = try AVCaptureDeviceInput(device: frontCameraDevice!)
            backCameraDeviceInput = try AVCaptureDeviceInput(device: backCameraDevice!)
        } catch let error as NSError {
            throw Error.avFoundationError(error)
        }
    }
    
    func setupVideoDeviceInput() throws {
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
        }
        
        guard let defaultVideoDevice = CameraController.defaultVideoDevice
        else {
            throw Error.noVideoDevice
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
            addInput(videoDeviceInput)
        } catch let error as NSError {
            throw Error.avFoundationError(error)
        }
    }
    
    func setupAudioDeviceInput() throws {
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
        }
        
        guard let defaultAudioDevice = CameraController.defaultAudioDevice
        else {
            throw Error.noAudioDevice
        }
        
        do {
            audioDeviceInput = try AVCaptureDeviceInput(device: defaultAudioDevice)
            addInput(audioDeviceInput)
        } catch let error as NSError {
            throw Error.avFoundationError(error)
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
            kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange as UInt32)
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
        videoConnection = videoDeviceOutput?.connection(with: AVMediaType.video)
        
        // TODO: Support different video orientations
        videoConnection?.videoOrientation = .portrait
        videoConnection?.preferredVideoStabilizationMode = .auto
    }
    
    func setupAudioConnection() {
        // Setup the audio connection
        audioConnection = audioDeviceOutput?.connection(with: AVMediaType.audio)
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
        return captureModes.contains(.photo)
    }
    
    var videoModeEnabled: Bool {
        return captureModes.contains(.video)
    }
    
    var slowMotionEnabled: Bool {
        return captureModes.contains(.slowMotionVideo)
    }
}

// MARK: AVFoundation Utilities

public extension CameraController {
    @objc public static var videoDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devices(for: .video)
    }
    
    @objc public static var audioDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devices(for: .audio)
    }
    
    @objc public static var defaultAudioDevice: AVCaptureDevice? {
        return AVCaptureDevice.default(for: .audio)
    }
    
    @objc public static var defaultVideoDevice: AVCaptureDevice? {
        return AVCaptureDevice.default(for: .video)
    }
    
    @objc public var inputDevices: [AVCaptureInput] {
        return captureSession.inputs
    }
    
    @objc public var outputDevices: [AVCaptureOutput] {
        return captureSession.outputs
    }
    
    @objc public var currentVideoDevice: AVCaptureDevice? {
        return videoDeviceInput?.device
    }
    
    @objc public var currentAudioDevice: AVCaptureDevice? {
        return audioDeviceInput?.device
    }
    
    @objc func videoDeviceForPosition(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return CameraController.videoDevices.filter { $0.position == position }.first
    }
    
    fileprivate func replaceCurrentVideoDeviceWithDevice(_ device: AVCaptureDevice) throws {
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput)
        } catch let error as NSError {
            throw Error.avFoundationError(error)
        }
    }
    
    fileprivate func replaceCurrentVideoDeviceInputWithDeviceInput(_ deviceInput: AVCaptureDeviceInput) {
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
        }
        
        videoDeviceInput = deviceInput
        addInput(deviceInput)
        
        setupVideoDeviceOutput()
        setupVideoConnection()
    }
    
    fileprivate func replaceCurrentAudioDeviceWithDevice(_ device: AVCaptureDevice) throws {
        do {
            let deviceInput = try AVCaptureDeviceInput(device: device)
            replaceCurrentAudioDeviceInputWithDeviceInput(deviceInput)
        } catch let error as NSError {
            throw Error.avFoundationError(error)
        }
    }
    
    fileprivate func replaceCurrentAudioDeviceInputWithDeviceInput(_ deviceInput: AVCaptureDeviceInput) {
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
        }
        
        audioDeviceInput = deviceInput
        addInput(deviceInput)
        
        setupAudioDeviceOutput()
        setupAudioConnection()
    }
    
}
