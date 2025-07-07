//
//  NextLevelVideoOutputManager.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

/// Manages video outputs for independent cameras with different settings
public class NextLevelVideoOutputManager: NSObject {
    
    // MARK: - Properties
    
    /// Video outputs mapped by camera position
    private var videoOutputs: [NextLevelDevicePosition: VideoOutputInfo] = [:]
    
    /// Active recordings
    private var activeRecordings: [NextLevelDevicePosition: RecordingInfo] = [:]
    
    /// Video processing queue
    private let videoQueue: DispatchQueue
    
    /// File output queue
    private let fileQueue: DispatchQueue
    
    /// Delegate
    public weak var delegate: NextLevelMultiCameraV2Delegate?
    
    /// File manager
    private let fileManager = FileManager.default
    
    /// Temporary directory for recordings
    private lazy var recordingDirectory: URL = {
        let tempDir = fileManager.temporaryDirectory
        let recordingDir = tempDir.appendingPathComponent("NextLevel/Recordings")
        try? fileManager.createDirectory(at: recordingDir, withIntermediateDirectories: true)
        return recordingDir
    }()
    
    // MARK: - Initialization
    
    public override init() {
        self.videoQueue = DispatchQueue(label: "com.nextlevel.video.output", qos: .userInitiated)
        self.fileQueue = DispatchQueue(label: "com.nextlevel.file.output", qos: .background)
        super.init()
    }
    
    // MARK: - Output Configuration
    
    /// Configure video output for a camera
    public func configureVideoOutput(for position: NextLevelDevicePosition,
                                   configuration: NextLevelCameraConfiguration,
                                   session: AVCaptureSession) throws {
        
        guard let videoConfig = configuration.videoConfiguration else {
            throw NextLevelError.invalidConfiguration("Video configuration required")
        }
        
        // Create video data output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Configure video settings
        var videoSettings: [String: Any] = [:]
        videoSettings[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_32BGRA
        videoDataOutput.videoSettings = videoSettings
        
        // Set sample buffer delegate
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        // Add to session
        guard session.canAddOutput(videoDataOutput) else {
            throw NextLevelError.unableToAddOutput
        }
        
        session.addOutput(videoDataOutput)
        
        // Configure connection
        if let connection = videoDataOutput.connection(with: .video) {
            // Apply stabilization
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = configuration.videoStabilizationMode
            }
            
            // Apply orientation
            connection.videoOrientation = configuration.orientation
            
            // Apply mirroring for front camera
            if configuration.cameraPosition == .front {
                connection.isVideoMirrored = true
            }
        }
        
        // Create movie file output
        let movieFileOutput = AVCaptureMovieFileOutput()
        
        // Configure movie output settings
        if let maxDuration = configuration.maximumRecordingDuration {
            movieFileOutput.maxRecordedDuration = maxDuration
        }
        
        // Configure output settings for the connection
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
            
            if let connection = movieFileOutput.connection(with: .video) {
                // Apply video settings
                let compressionSettings: [String: Any] = [
                    AVVideoAverageBitRateKey: videoConfig.bitRate,
                    AVVideoExpectedSourceFrameRateKey: configuration.preferredFrameRate,
                    AVVideoMaxKeyFrameIntervalKey: videoConfig.maxKeyFrameInterval,
                    AVVideoProfileLevelKey: videoConfig.profileLevel
                ]
                
                let outputSettings: [String: Any] = [
                    AVVideoCodecKey: videoConfig.codec,
                    AVVideoCompressionPropertiesKey: compressionSettings
                ]
                
                movieFileOutput.setOutputSettings(outputSettings, for: connection)
                
                // Apply stabilization
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = configuration.videoStabilizationMode
                }
            }
        } else {
            // Clean up video data output if movie output fails
            session.removeOutput(videoDataOutput)
            throw NextLevelError.unableToAddOutput
        }
        
        // Store output info
        let outputInfo = VideoOutputInfo(
            position: position,
            videoDataOutput: videoDataOutput,
            movieFileOutput: movieFileOutput,
            configuration: configuration,
            videoConfig: videoConfig
        )
        
        videoOutputs[position] = outputInfo
    }
    
    /// Remove video output for a camera
    public func removeVideoOutput(for position: NextLevelDevicePosition, session: AVCaptureSession) {
        guard let outputInfo = videoOutputs[position] else { return }
        
        // Stop recording if active
        if activeRecordings[position] != nil {
            stopRecording(at: position)
        }
        
        // Remove outputs from session
        session.removeOutput(outputInfo.videoDataOutput)
        session.removeOutput(outputInfo.movieFileOutput)
        
        // Remove from storage
        videoOutputs.removeValue(forKey: position)
    }
    
    // MARK: - Recording Control
    
    /// Start recording for a specific camera
    public func startRecording(at position: NextLevelDevicePosition) throws {
        guard let outputInfo = videoOutputs[position] else {
            throw NextLevelError.deviceNotAvailable
        }
        
        // Check if already recording
        if activeRecordings[position] != nil {
            throw NextLevelError.unknown
        }
        
        // Generate unique filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "camera_\(position.rawValue)_\(timestamp).mov"
        let fileURL = recordingDirectory.appendingPathComponent(filename)
        
        // Create recording info
        let recordingInfo = RecordingInfo(
            position: position,
            fileURL: fileURL,
            startTime: Date(),
            configuration: outputInfo.configuration
        )
        
        activeRecordings[position] = recordingInfo
        
        // Start recording to file
        outputInfo.movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didStartVideoRecording: position)
        }
    }
    
    /// Stop recording for a specific camera
    public func stopRecording(at position: NextLevelDevicePosition) {
        guard let outputInfo = videoOutputs[position],
              activeRecordings[position] != nil else { return }
        
        outputInfo.movieFileOutput.stopRecording()
    }
    
    /// Pause recording for a specific camera
    public func pauseRecording(at position: NextLevelDevicePosition) {
        guard let outputInfo = videoOutputs[position],
              let recordingInfo = activeRecordings[position],
              !recordingInfo.isPaused else { return }
        
        if #available(iOS 18.0, *) {
            if outputInfo.movieFileOutput.isRecordingPaused {
                return
            }
            outputInfo.movieFileOutput.pauseRecording()
        }
        activeRecordings[position]?.isPaused = true
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didPauseVideoRecording: position)
        }
    }
    
    /// Resume recording for a specific camera
    public func resumeRecording(at position: NextLevelDevicePosition) {
        guard let outputInfo = videoOutputs[position],
              let recordingInfo = activeRecordings[position],
              recordingInfo.isPaused else { return }
        
        if #available(iOS 18.0, *) {
            outputInfo.movieFileOutput.resumeRecording()
        }
        activeRecordings[position]?.isPaused = false
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didResumeVideoRecording: position)
        }
    }
    
    // MARK: - Status
    
    /// Check if camera is recording
    public func isRecording(at position: NextLevelDevicePosition) -> Bool {
        return activeRecordings[position] != nil
    }
    
    /// Get recording duration for a camera
    public func recordingDuration(at position: NextLevelDevicePosition) -> CMTime? {
        guard let outputInfo = videoOutputs[position] else { return nil }
        return outputInfo.movieFileOutput.recordedDuration
    }
    
    /// Get recording file size for a camera
    public func recordingFileSize(at position: NextLevelDevicePosition) -> Int64? {
        guard let outputInfo = videoOutputs[position] else { return nil }
        return outputInfo.movieFileOutput.recordedFileSize
    }
    
    // MARK: - Buffer Processing
    
    /// Process video buffer for specific camera
    private func processVideoBuffer(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition) {
        // Update recording progress if active
        if let recordingInfo = activeRecordings[position] {
            let duration = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds - recordingInfo.startTime.timeIntervalSince1970
            let progress = Float(duration / (recordingInfo.configuration.maximumRecordingDuration?.seconds ?? Double.infinity))
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nextLevel(
                    NextLevel.shared,
                    didUpdateVideoRecordingProgress: min(progress, 1.0),
                    duration: CMTime(seconds: duration, preferredTimescale: 600),
                    forCamera: position
                )
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension NextLevelVideoOutputManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Find which camera this output belongs to
        guard let position = videoOutputs.first(where: { $0.value.videoDataOutput == output })?.key else { return }
        
        // Process buffer
        processVideoBuffer(sampleBuffer, from: position)
        
        // Notify delegate
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didProcessVideoFrame: sampleBuffer, fromCamera: position, timestamp: timestamp)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Find which camera dropped the frame
        guard let position = videoOutputs.first(where: { $0.value.videoDataOutput == output })?.key else { return }
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nextLevel(NextLevel.shared, didDropFrame: position, reason: "Video buffer dropped")
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension NextLevelVideoOutputManager: AVCaptureFileOutputRecordingDelegate {
    
    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started successfully
    }
    
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Find which camera this recording belongs to
        guard let position = videoOutputs.first(where: { $0.value.movieFileOutput == output })?.key else { return }
        
        // Remove from active recordings
        let recordingInfo = activeRecordings.removeValue(forKey: position)
        
        if let error = error {
            // Handle recording error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nextLevel(NextLevel.shared, camera: position, didEncounterError: error)
                self.delegate?.nextLevel(NextLevel.shared, didCompleteVideoRecording: position, url: nil)
            }
        } else {
            // Recording completed successfully
            fileQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Process the recorded file if needed
                if let recordingInfo = recordingInfo {
                    self.processRecordedFile(outputFileURL, for: position, recordingInfo: recordingInfo)
                }
                
                DispatchQueue.main.async {
                    self.delegate?.nextLevel(NextLevel.shared, didCompleteVideoRecording: position, url: outputFileURL)
                }
            }
        }
    }
    
    public func fileOutput(_ output: AVCaptureFileOutput, didPauseRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording paused
    }
    
    public func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording resumed
    }
    
    // MARK: - File Processing
    
    private func processRecordedFile(_ fileURL: URL, for position: NextLevelDevicePosition, recordingInfo: RecordingInfo) {
        // Add metadata
        // Could add custom metadata here based on video configuration
        
        // Apply any post-processing if needed
        // For now, just keep the file as-is
    }
}

// MARK: - Supporting Types

/// Information about a video output
private struct VideoOutputInfo {
    let position: NextLevelDevicePosition
    let videoDataOutput: AVCaptureVideoDataOutput
    let movieFileOutput: AVCaptureMovieFileOutput
    let configuration: NextLevelCameraConfiguration
    let videoConfig: NextLevelVideoConfiguration
}

/// Information about an active recording
private class RecordingInfo {
    let position: NextLevelDevicePosition
    let fileURL: URL
    let startTime: Date
    let configuration: NextLevelCameraConfiguration
    var isPaused: Bool = false
    
    init(position: NextLevelDevicePosition, fileURL: URL, startTime: Date, configuration: NextLevelCameraConfiguration) {
        self.position = position
        self.fileURL = fileURL
        self.startTime = startTime
        self.configuration = configuration
    }
}

// MARK: - Errors

// Use existing error cases from NextLevel.swift