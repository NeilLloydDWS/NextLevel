//
//  NextLevelPhotoOutputManager.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreImage
import UIKit

/// Manages photo outputs for independent cameras with different settings
public class NextLevelPhotoOutputManager: NSObject {
    
    // MARK: - Properties
    
    /// Photo outputs mapped by camera position
    private var photoOutputs: [NextLevelDevicePosition: PhotoOutputInfo] = [:]
    
    /// Active capture requests
    private var activeCaptureRequests: [NextLevelDevicePosition: PhotoCaptureRequest] = [:]
    
    /// Photo processing queue
    private let photoQueue: DispatchQueue
    
    /// Delegate
    public weak var delegate: NextLevelMultiCameraV2Delegate?
    
    /// Photo processor for advanced processing
    private let photoProcessor = PhotoProcessor()
    
    // MARK: - Initialization
    
    public override init() {
        self.photoQueue = DispatchQueue(label: "com.nextlevel.photo.output", qos: .userInitiated)
        super.init()
    }
    
    // MARK: - Output Configuration
    
    /// Configure photo output for a camera
    public func configurePhotoOutput(for position: NextLevelDevicePosition,
                                   configuration: NextLevelCameraConfiguration,
                                   session: AVCaptureSession) throws {
        
        guard let photoConfig = configuration.photoConfiguration else {
            throw NextLevelError.invalidConfiguration("Photo configuration required")
        }
        
        // Create photo output
        let photoOutput = AVCapturePhotoOutput()
        
        // Configure photo output settings
        photoOutput.isHighResolutionCaptureEnabled = photoConfig.isHighResolutionEnabled
        
        // Set available photo codecs
        if photoOutput.availablePhotoCodecTypes.contains(photoConfig.codec) {
            // Will be set per capture
        }
        
        // Configure depth data if available
        // Depth data configuration would go here if supported
        
        // Configure portrait effects matte if available
        if #available(iOS 12.0, *) {
            // Portrait effects matte configuration would go here
        }
        
        // Set max photo quality
        photoOutput.maxPhotoQualityPrioritization = .quality
        
        // Add to session
        guard session.canAddOutput(photoOutput) else {
            throw NextLevelError.unableToAddOutput
        }
        
        session.addOutput(photoOutput)
        
        // Configure connection
        if let connection = photoOutput.connection(with: .video) {
            // Apply orientation
            connection.videoOrientation = configuration.orientation
            
            // Apply mirroring for front camera
            if configuration.cameraPosition == .front {
                connection.isVideoMirrored = true
            }
        }
        
        // Store output info
        let outputInfo = PhotoOutputInfo(
            position: position,
            photoOutput: photoOutput,
            configuration: configuration,
            photoConfig: photoConfig
        )
        
        photoOutputs[position] = outputInfo
    }
    
    /// Remove photo output for a camera
    public func removePhotoOutput(for position: NextLevelDevicePosition, session: AVCaptureSession) {
        guard let outputInfo = photoOutputs[position] else { return }
        
        // Cancel any active captures
        activeCaptureRequests.removeValue(forKey: position)
        
        // Remove output from session
        session.removeOutput(outputInfo.photoOutput)
        
        // Remove from storage
        photoOutputs.removeValue(forKey: position)
    }
    
    // MARK: - Photo Capture
    
    /// Capture photo from specific camera
    public func capturePhoto(at position: NextLevelDevicePosition,
                           flashMode: NextLevelFlashMode? = nil,
                           completion: @escaping (Result<PhotoCaptureResult, Error>) -> Void) {
        
        guard let outputInfo = photoOutputs[position] else {
            completion(.failure(NextLevelError.deviceNotAvailable))
            return
        }
        
        // Check if already capturing
        if activeCaptureRequests[position] != nil {
            completion(.failure(NextLevelError.unknown))
            return
        }
        
        // Create photo settings
        let photoSettings = createPhotoSettings(for: outputInfo, flashMode: flashMode)
        
        // Create capture request
        let captureRequest = PhotoCaptureRequest(
            position: position,
            settings: photoSettings,
            completion: completion
        )
        
        activeCaptureRequests[position] = captureRequest
        
        // Create photo capture delegate
        let captureDelegate = PhotoCaptureDelegate(
            position: position,
            configuration: outputInfo.configuration,
            photoConfig: outputInfo.photoConfig,
            manager: self
        )
        
        // Notify delegate that capture will begin
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, willCapturePhoto: position)
        }
        
        // Capture photo
        outputInfo.photoOutput.capturePhoto(with: photoSettings, delegate: captureDelegate)
    }
    
    /// Capture photo with specific settings
    public func capturePhoto(at position: NextLevelDevicePosition,
                           settings: AVCapturePhotoSettings,
                           completion: @escaping (Result<PhotoCaptureResult, Error>) -> Void) {
        
        guard let outputInfo = photoOutputs[position] else {
            completion(.failure(NextLevelError.deviceNotAvailable))
            return
        }
        
        // Check if already capturing
        if activeCaptureRequests[position] != nil {
            completion(.failure(NextLevelError.unknown))
            return
        }
        
        // Create capture request
        let captureRequest = PhotoCaptureRequest(
            position: position,
            settings: settings,
            completion: completion
        )
        
        activeCaptureRequests[position] = captureRequest
        
        // Create photo capture delegate
        let captureDelegate = PhotoCaptureDelegate(
            position: position,
            configuration: outputInfo.configuration,
            photoConfig: outputInfo.photoConfig,
            manager: self
        )
        
        // Notify delegate that capture will begin
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, willCapturePhoto: position)
        }
        
        // Capture photo
        outputInfo.photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
    }
    
    // MARK: - Private Methods
    
    private func createPhotoSettings(for outputInfo: PhotoOutputInfo, flashMode: NextLevelFlashMode?) -> AVCapturePhotoSettings {
        let photoConfig = outputInfo.photoConfig
        
        // Create settings with appropriate format
        let photoSettings: AVCapturePhotoSettings
        
        if photoConfig.codec == .hevc,
           outputInfo.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else if outputInfo.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            photoSettings = AVCapturePhotoSettings()
        }
        
        // Configure flash
        if let flashMode = flashMode {
            if outputInfo.photoOutput.supportedFlashModes.contains(flashMode) {
                photoSettings.flashMode = flashMode
            }
        } else if photoConfig.flashMode != .off {
            if outputInfo.photoOutput.supportedFlashModes.contains(photoConfig.flashMode) {
                photoSettings.flashMode = photoConfig.flashMode
            }
        }
        
        // Configure quality
        photoSettings.photoQualityPrioritization = .quality
        
        // Configure HDR
        if #available(iOS 13.0, *) {
            photoSettings.photoQualityPrioritization = .quality
        }
        
        // Configure depth data
        // Depth data delivery configuration
        
        // Configure portrait effects matte
        if #available(iOS 12.0, *) {
            // Portrait effects matte delivery configuration
        }
        
        return photoSettings
    }
    
    fileprivate func handleCaptureCompletion(for position: NextLevelDevicePosition, result: Result<PhotoCaptureResult, Error>) {
        // Remove from active requests
        if let request = activeCaptureRequests.removeValue(forKey: position) {
            // Call completion handler
            request.completion(result)
        }
        
        // Notify delegate
        switch result {
        case .success(let captureResult):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nextLevel(
                    NextLevel.shared,
                    didProcessPhoto: captureResult.photoData,
                    fromCamera: position,
                    metadata: captureResult.metadata
                )
            }
            
        case .failure(let error):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nextLevel(NextLevel.shared, camera: position, didEncounterError: error)
            }
        }
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    
    let position: NextLevelDevicePosition
    let configuration: NextLevelCameraConfiguration
    let photoConfig: NextLevelPhotoConfiguration
    weak var manager: NextLevelPhotoOutputManager?
    
    private var photoData: Data?
    private var metadata: [String: Any] = [:]
    
    init(position: NextLevelDevicePosition,
         configuration: NextLevelCameraConfiguration,
         photoConfig: NextLevelPhotoConfiguration,
         manager: NextLevelPhotoOutputManager) {
        self.position = position
        self.configuration = configuration
        self.photoConfig = photoConfig
        self.manager = manager
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Capture is about to begin
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Flash fired or shutter sound should play
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Photo captured, processing begins
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            let result = Result<PhotoCaptureResult, Error>.failure(error)
            manager?.handleCaptureCompletion(for: position, result: result)
            return
        }
        
        // Get photo data
        guard let data = photo.fileDataRepresentation() else {
            let result = Result<PhotoCaptureResult, Error>.failure(NextLevelError.unknown)
            manager?.handleCaptureCompletion(for: position, result: result)
            return
        }
        
        self.photoData = data
        
        // Extract metadata
        metadata["dimensions"] = [
            "width": photo.pixelBuffer != nil ? CVPixelBufferGetWidth(photo.pixelBuffer!) : 0,
            "height": photo.pixelBuffer != nil ? CVPixelBufferGetHeight(photo.pixelBuffer!) : 0
        ]
        
        metadata["timestamp"] = photo.timestamp
        metadata["isRawPhoto"] = photo.isRawPhoto
        
        // Get depth data if available
        if let depthData = photo.depthData {
            metadata["hasDepthData"] = true
            metadata["depthDataAccuracy"] = depthData.depthDataAccuracy.rawValue
        }
        
        // Get portrait effects matte if available
        if #available(iOS 12.0, *) {
            if let portraitMatte = photo.portraitEffectsMatte {
                metadata["hasPortraitEffectsMatte"] = true
                metadata["portraitMatteType"] = portraitMatte.pixelFormatType
            }
        }
        
        // Notify main delegate
        if let manager = manager {
            manager.delegate?.nextLevel(NextLevel.shared, didCapturePhoto: photo, fromCamera: position)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            let result = Result<PhotoCaptureResult, Error>.failure(error)
            manager?.handleCaptureCompletion(for: position, result: result)
            return
        }
        
        guard let photoData = photoData else {
            let result = Result<PhotoCaptureResult, Error>.failure(NextLevelError.unknown)
            manager?.handleCaptureCompletion(for: position, result: result)
            return
        }
        
        // Process photo if needed
        if false { // Photo processing check
            processPhoto(data: photoData)
        } else {
            // Return unprocessed photo
            let captureResult = PhotoCaptureResult(
                photoData: photoData,
                metadata: metadata,
                position: position
            )
            
            let result = Result<PhotoCaptureResult, Error>.success(captureResult)
            manager?.handleCaptureCompletion(for: position, result: result)
        }
    }
    
    private func processPhoto(data: Data) {
        // Apply any processing
        // Photo processing would go here
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let captureResult = PhotoCaptureResult(
                photoData: data,
                metadata: self.metadata,
                position: self.position
            )
            
            let result = Result<PhotoCaptureResult, Error>.success(captureResult)
            self.manager?.handleCaptureCompletion(for: self.position, result: result)
        }
    }
}

// MARK: - Photo Processor

private class PhotoProcessor {
    
    private let processingQueue = DispatchQueue(label: "com.nextlevel.photo.processing", qos: .userInitiated)
    private let context = CIContext()
    
    func processPhoto(data: Data, configuration: NextLevelPhotoConfiguration, completion: @escaping (Data?) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self,
                  let image = CIImage(data: data) else {
                completion(nil)
                return
            }
            
            var processedImage = image
            
            // Apply filters if configured
            // Auto-enhance and custom filters would be implemented here
            // if configuration had those properties
            
            // Convert back to data
            if let cgImage = self.context.createCGImage(processedImage, from: processedImage.extent) {
                let processedData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) // Default quality
                completion(processedData)
            } else {
                completion(nil)
            }
        }
    }
    
    private func autoEnhance(image: CIImage) -> CIImage {
        let filters = image.autoAdjustmentFilters()
        var enhanced = image
        
        for filter in filters {
            filter.setValue(enhanced, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                enhanced = output
            }
        }
        
        return enhanced
    }
    
    private func applyFilter(_ filterName: String, to image: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: filterName) else { return nil }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage
    }
}

// MARK: - Supporting Types

/// Information about a photo output
private struct PhotoOutputInfo {
    let position: NextLevelDevicePosition
    let photoOutput: AVCapturePhotoOutput
    let configuration: NextLevelCameraConfiguration
    let photoConfig: NextLevelPhotoConfiguration
}

/// Active photo capture request
private struct PhotoCaptureRequest {
    let position: NextLevelDevicePosition
    let settings: AVCapturePhotoSettings
    let completion: (Result<PhotoCaptureResult, Error>) -> Void
}

/// Photo capture result
public struct PhotoCaptureResult {
    public let photoData: Data
    public let metadata: [String: Any]
    public let position: NextLevelDevicePosition
}

// MARK: - Errors

// Use existing error cases from NextLevel.swift