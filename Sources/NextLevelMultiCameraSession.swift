//
//  NextLevelMultiCameraSession.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

/// Manages multiple camera inputs and outputs for independent configuration
public class NextLevelMultiCameraSession: NSObject {
    
    // MARK: - Properties
    
    /// The AVCaptureMultiCamSession instance
    public let captureSession: AVCaptureMultiCamSession
    
    /// Camera inputs mapped by position
    private var cameraInputs: [NextLevelDevicePosition: AVCaptureDeviceInput] = [:]
    
    /// Video data outputs mapped by position
    private var videoOutputs: [NextLevelDevicePosition: AVCaptureVideoDataOutput] = [:]
    
    /// Photo outputs mapped by position
    private var photoOutputs: [NextLevelDevicePosition: AVCapturePhotoOutput] = [:]
    
    /// Movie file outputs mapped by position
    private var movieOutputs: [NextLevelDevicePosition: AVCaptureMovieFileOutput] = [:]
    
    /// Audio input
    private var audioInput: AVCaptureDeviceInput?
    
    /// Active capture modes per camera
    private var activeModes: [NextLevelDevicePosition: NextLevelCaptureMode] = [:]
    
    /// Camera configurations
    private var cameraConfigurations: [NextLevelDevicePosition: NextLevelCameraConfiguration] = [:]
    
    /// Resource manager
    private let resourceManager: CameraResourceManager
    
    /// Session queue for configuration changes
    private let sessionQueue: DispatchQueue
    
    /// Video processing queue
    private let videoQueue: DispatchQueue
    
    /// Delegate
    public weak var delegate: NextLevelMultiCameraV2Delegate?
    
    // MARK: - Initialization
    
    public override init() {
        self.captureSession = AVCaptureMultiCamSession()
        self.resourceManager = CameraResourceManager()
        self.sessionQueue = DispatchQueue(label: "com.nextlevel.multicamera.session", qos: .userInitiated)
        self.videoQueue = DispatchQueue(label: "com.nextlevel.multicamera.video", qos: .userInitiated)
        
        super.init()
        
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Configure the session with multi-camera configuration
    public func configure(with configuration: NextLevelMultiCameraConfigurationV2, completion: @escaping (Error?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Validate configuration
                let validation = configuration.validate()
                if !validation.isValid {
                    throw NextLevelError.invalidConfiguration(validation.errors.joined(separator: ", "))
                }
                
                // Check resource availability
                if !self.resourceManager.canAccommodate(configuration) {
                    throw NextLevelError.insufficientResources
                }
                
                self.captureSession.beginConfiguration()
                defer { self.captureSession.commitConfiguration() }
                
                // Remove existing inputs/outputs
                self.removeAllInputsAndOutputs()
                
                // Add cameras based on configuration
                for (position, cameraConfig) in configuration.cameraConfigurations {
                    try self.addCamera(at: position, with: cameraConfig)
                }
                
                // Add audio if configured
                if let audioConfig = configuration.audioConfiguration,
                   let audioSource = configuration.audioSource {
                    try self.addAudioInput(from: audioSource, config: audioConfig)
                }
                
                completion(nil)
                
            } catch {
                completion(error)
            }
        }
    }
    
    /// Add or update a camera
    public func addCamera(at position: NextLevelDevicePosition, with configuration: NextLevelCameraConfiguration) throws {
        // Find the appropriate device
        guard let device = NextLevelDeviceMapping.device(
            for: NextLevelDevicePositionExtended(avPosition: position),
            lensType: configuration.lensType
        ) else {
            throw NextLevelError.deviceNotAvailable
        }
        
        // Create and add input
        let input = try AVCaptureDeviceInput(device: device)
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            cameraInputs[position] = input
            cameraConfigurations[position] = configuration
            activeModes[position] = configuration.captureMode
            
            // Apply device configuration
            try configuration.applyTo(device: device)
            
            // Add appropriate outputs
            switch configuration.captureMode {
            case .video, .multiCameraWithoutAudio:
                try addVideoOutputs(for: position, device: device, configuration: configuration)
            case .photo:
                try addPhotoOutput(for: position, device: device, configuration: configuration)
            default:
                throw NextLevelError.unknown
            }
            
            // Notify delegate
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nextLevel(NextLevel.shared, didAddCamera: position, with: configuration)
            }
            
        } else {
            throw NextLevelError.unableToAddInput
        }
    }
    
    /// Remove a camera
    public func removeCamera(at position: NextLevelDevicePosition) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }
            
            // Remove input
            if let input = self.cameraInputs[position] {
                self.captureSession.removeInput(input)
                self.cameraInputs.removeValue(forKey: position)
            }
            
            // Remove outputs
            if let videoOutput = self.videoOutputs[position] {
                self.captureSession.removeOutput(videoOutput)
                self.videoOutputs.removeValue(forKey: position)
            }
            
            if let photoOutput = self.photoOutputs[position] {
                self.captureSession.removeOutput(photoOutput)
                self.photoOutputs.removeValue(forKey: position)
            }
            
            if let movieOutput = self.movieOutputs[position] {
                self.captureSession.removeOutput(movieOutput)
                self.movieOutputs.removeValue(forKey: position)
            }
            
            // Clean up
            self.activeModes.removeValue(forKey: position)
            self.cameraConfigurations.removeValue(forKey: position)
            
            // Notify delegate
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nextLevel(NextLevel.shared, didRemoveCamera: position)
            }
        }
    }
    
    /// Update camera configuration
    public func updateCameraConfiguration(at position: NextLevelDevicePosition, configuration: NextLevelCameraConfiguration) throws {
        guard let input = cameraInputs[position] else {
            throw NextLevelError.deviceNotAvailable
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }
            
            do {
                // Apply new configuration to device
                try configuration.applyTo(device: input.device)
                
                // Update stored configuration
                self.cameraConfigurations[position] = configuration
                
                // Update outputs if capture mode changed
                if self.activeModes[position] != configuration.captureMode {
                    self.removeOutputs(for: position)
                    
                    switch configuration.captureMode {
                    case .video, .multiCameraWithoutAudio:
                        try self.addVideoOutputs(for: position, device: input.device, configuration: configuration)
                    case .photo:
                        try self.addPhotoOutput(for: position, device: input.device, configuration: configuration)
                    default:
                        break
                    }
                    
                    self.activeModes[position] = configuration.captureMode
                }
                
                // Notify delegate
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.nextLevel(NextLevel.shared, didUpdateConfiguration: configuration, forCamera: position)
                }
                
            } catch {
                // Notify error
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.nextLevel(NextLevel.shared, camera: position, didEncounterError: error)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Monitor session runtime errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
        
        // Monitor session interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
    }
    
    private func removeAllInputsAndOutputs() {
        // Remove all inputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        
        // Remove all outputs
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        // Clear collections
        cameraInputs.removeAll()
        videoOutputs.removeAll()
        photoOutputs.removeAll()
        movieOutputs.removeAll()
        audioInput = nil
        activeModes.removeAll()
        cameraConfigurations.removeAll()
    }
    
    private func addVideoOutputs(for position: NextLevelDevicePosition, device: AVCaptureDevice, configuration: NextLevelCameraConfiguration) throws {
        // Add video data output for processing
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Configure video settings based on configuration
        if let videoConfig = configuration.videoConfiguration {
            var videoSettings: [String: Any] = [:]
            
            // Set pixel format
            videoSettings[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_32BGRA
            
            // Apply settings
            videoOutput.videoSettings = videoSettings
        }
        
        // Set delegate
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            videoOutputs[position] = videoOutput
            
            // Configure connection
            if let connection = videoOutput.connection(with: .video) {
                // Apply stabilization if requested
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = configuration.videoStabilizationMode
                }
                
                // Apply orientation
                connection.videoOrientation = configuration.orientation
            }
        } else {
            throw NextLevelError.unableToAddOutput
        }
        
        // Add movie file output for recording
        let movieOutput = AVCaptureMovieFileOutput()
        
        if let videoConfig = configuration.videoConfiguration {
            // Configure recording settings
            movieOutput.maxRecordedDuration = configuration.maximumRecordingDuration ?? CMTime.invalid
            
            // Set video codec and bitrate
            var outputSettings: [String: Any] = [:]
            outputSettings[AVVideoCodecKey] = videoConfig.codec
            outputSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: videoConfig.bitRate
            ]
            
            if let connection = movieOutput.connection(with: .video) {
                movieOutput.setOutputSettings(outputSettings, for: connection)
            }
        }
        
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            movieOutputs[position] = movieOutput
        }
    }
    
    private func addPhotoOutput(for position: NextLevelDevicePosition, device: AVCaptureDevice, configuration: NextLevelCameraConfiguration) throws {
        let photoOutput = AVCapturePhotoOutput()
        
        // Configure photo output based on configuration
        if let photoConfig = configuration.photoConfiguration {
            photoOutput.isHighResolutionCaptureEnabled = photoConfig.isHighResolutionEnabled
            
            // Set available photo codecs
            if photoOutput.availablePhotoCodecTypes.contains(photoConfig.codec) {
                photoOutput.maxPhotoQualityPrioritization = .quality
            }
        }
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutputs[position] = photoOutput
        } else {
            throw NextLevelError.unableToAddOutput
        }
    }
    
    private func addAudioInput(from position: NextLevelDevicePosition, config: NextLevelAudioConfiguration) throws {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw NextLevelError.deviceNotAvailable
        }
        
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
            self.audioInput = audioInput
        } else {
            throw NextLevelError.unableToAddInput
        }
    }
    
    private func removeOutputs(for position: NextLevelDevicePosition) {
        if let videoOutput = videoOutputs[position] {
            captureSession.removeOutput(videoOutput)
            videoOutputs.removeValue(forKey: position)
        }
        
        if let photoOutput = photoOutputs[position] {
            captureSession.removeOutput(photoOutput)
            photoOutputs.removeValue(forKey: position)
        }
        
        if let movieOutput = movieOutputs[position] {
            captureSession.removeOutput(movieOutput)
            movieOutputs.removeValue(forKey: position)
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
        
        // Determine which camera caused the error
        let affectedPosition: NextLevelDevicePosition? = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didEncounterRuntimeError: error, forCamera: affectedPosition)
        }
    }
    
    @objc private func sessionWasInterrupted(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? AVCaptureSession.InterruptionReason else { return }
        
        // Handle interruption based on reason
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            // Pause recording if needed
            break
        case .videoDeviceInUseByAnotherClient:
            // Another app is using the camera
            break
        default:
            break
        }
    }
    
    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        // Resume operations
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension NextLevelMultiCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Determine which camera this output is from
        guard let position = videoOutputs.first(where: { $0.value == output })?.key else { return }
        
        // Get timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didProcessVideoFrame: sampleBuffer, fromCamera: position, timestamp: timestamp)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Determine which camera dropped the frame
        guard let position = videoOutputs.first(where: { $0.value == output })?.key else { return }
        
        // Get drop reason
        var reason = "Unknown"
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[String: Any]],
           let attachment = attachments.first,
           attachment[kCMSampleBufferAttachmentKey_DroppedFrameReason as String] != nil {
            reason = "Late arrival"
        }
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didDropFrame: position, reason: reason)
        }
    }
}

// MARK: - Resource Management

/// Manages camera resources and validates configurations
public class CameraResourceManager {
    
    // MARK: - Properties
    
    private var activeResources: Set<CameraResource> = []
    private var thermalState: ProcessInfo.ThermalState = .nominal
    private let processInfo = ProcessInfo.processInfo
    
    // MARK: - Resource Types
    
    struct CameraResource: Hashable {
        let position: NextLevelDevicePosition
        let captureMode: NextLevelCaptureMode
        let resolution: String
        let frameRate: Int
        
        var estimatedBandwidth: Int {
            // Rough bandwidth estimation in Mbps
            switch resolution {
            case "4K":
                return frameRate >= 60 ? 200 : 100
            case "1080p":
                return frameRate >= 60 ? 50 : 25
            case "720p":
                return frameRate >= 60 ? 25 : 15
            default:
                return 10
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if the system can accommodate a configuration
    public func canAccommodate(_ configuration: NextLevelMultiCameraConfigurationV2) -> Bool {
        // Check device capabilities
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            return false
        }
        
        // Check camera count
        if configuration.cameraCount > configuration.maximumSimultaneousCameras {
            return false
        }
        
        // Estimate total bandwidth
        var totalBandwidth = 0
        for (_, cameraConfig) in configuration.cameraConfigurations {
            let resource = createResource(from: cameraConfig)
            totalBandwidth += resource.estimatedBandwidth
        }
        
        // Check thermal state constraints
        let maxBandwidth = maxBandwidthForThermalState()
        return totalBandwidth <= maxBandwidth
    }
    
    /// Validate configurations
    public func validateConfigurations(_ configs: [NextLevelCameraConfiguration]) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Check for duplicate positions
        var positions = Set<NextLevelDevicePosition>()
        for config in configs {
            if positions.contains(config.cameraPosition) {
                errors.append(ValidationError(message: "Duplicate camera position: \(config.cameraPosition)"))
            }
            positions.insert(config.cameraPosition)
        }
        
        // Validate individual configurations
        for config in configs {
            let (isValid, configErrors) = config.validate()
            if !isValid {
                errors.append(contentsOf: configErrors.map { ValidationError(message: $0) })
            }
        }
        
        return errors
    }
    
    /// Get recommended adjustments for thermal state
    public func optimizeForThermalState() -> [ConfigurationAdjustment] {
        var adjustments: [ConfigurationAdjustment] = []
        
        switch thermalState {
        case .fair:
            // Reduce non-essential frame rates
            adjustments.append(ConfigurationAdjustment(
                type: .frameRate,
                priority: .medium,
                newValue: 24,
                reason: "Thermal throttling - fair state"
            ))
            
        case .serious:
            // Disable low priority cameras
            adjustments.append(ConfigurationAdjustment(
                type: .disableCamera,
                priority: .low,
                newValue: false,
                reason: "Thermal throttling - serious state"
            ))
            
        case .critical:
            // Keep only essential cameras
            adjustments.append(ConfigurationAdjustment(
                type: .disableCamera,
                priority: .medium,
                newValue: false,
                reason: "Thermal throttling - critical state"
            ))
            
        default:
            break
        }
        
        return adjustments
    }
    
    // MARK: - Private Methods
    
    private func createResource(from config: NextLevelCameraConfiguration) -> CameraResource {
        var resolution = "1080p"
        
        if let videoConfig = config.videoConfiguration {
            switch videoConfig.preset {
            case .hd4K3840x2160:
                resolution = "4K"
            case .hd1920x1080:
                resolution = "1080p"
            case .hd1280x720:
                resolution = "720p"
            default:
                resolution = "SD"
            }
        }
        
        return CameraResource(
            position: config.cameraPosition,
            captureMode: config.captureMode,
            resolution: resolution,
            frameRate: config.preferredFrameRate
        )
    }
    
    private func maxBandwidthForThermalState() -> Int {
        switch thermalState {
        case .nominal:
            return 400 // Mbps
        case .fair:
            return 300
        case .serious:
            return 200
        case .critical:
            return 100
        @unknown default:
            return 200
        }
    }
}

// MARK: - Supporting Types

public struct ValidationError {
    public let message: String
}

public struct ConfigurationAdjustment {
    public enum AdjustmentType {
        case frameRate
        case resolution
        case disableCamera
        case quality
    }
    
    public let type: AdjustmentType
    public let priority: CameraPriority
    public let newValue: Any
    public let reason: String
}