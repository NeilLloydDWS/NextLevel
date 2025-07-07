//
//  NextLevelMultiCameraRecording.swift
//  NextLevel (http://github.com/NextLevel/)
//
//  Copyright (c) 2016-present patrick piemonte (http://patrickpiemonte.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import UIKit
import Foundation
import AVFoundation
import CoreVideo

// MARK: - types

/// Multi-camera recording state
public enum MultiCameraRecordingState {
    case idle
    case preparing
    case recording
    case paused
    case finishing
}

/// Multi-camera recording error types
public enum MultiCameraRecordingError: Error, CustomStringConvertible {
    case invalidConfiguration
    case writerCreationFailed
    case inputCreationFailed
    case notReadyToRecord
    case recordingInProgress
    case noRecordingInProgress
    case synchronizationFailed
    
    public var description: String {
        switch self {
        case .invalidConfiguration:
            return "Invalid multi-camera recording configuration"
        case .writerCreationFailed:
            return "Failed to create asset writer"
        case .inputCreationFailed:
            return "Failed to create asset writer input"
        case .notReadyToRecord:
            return "Not ready to start recording"
        case .recordingInProgress:
            return "Recording already in progress"
        case .noRecordingInProgress:
            return "No recording in progress"
        case .synchronizationFailed:
            return "Failed to synchronize camera streams"
        }
    }
}

// MARK: - NextLevelMultiCameraRecording

/// Multi-camera recording manager for NextLevel
public class NextLevelMultiCameraRecording {
    
    // MARK: - properties
    
    /// Current recording state
    public private(set) var state: MultiCameraRecordingState = .idle
    
    /// Recording mode from configuration
    public let recordingMode: MultiCameraRecordingMode
    
    /// Multi-camera configuration reference
    public weak var configuration: NextLevelMultiCameraConfiguration?
    
    /// Output directory for recordings
    public var outputDirectory: URL = {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let outputPath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NextLevel", isDirectory: true)
        
        // Create directory if needed
        do {
            try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("NextLevel, failed to create output directory: \(error)")
        }
        
        return outputPath
    }()
    
    /// File name prefix
    public var fileNamePrefix: String = "MultiCamera"
    
    // Private properties
    private var assetWriters: [NextLevelDevicePosition: AVAssetWriter] = [:]
    private var videoInputs: [NextLevelDevicePosition: AVAssetWriterInput] = [:]
    private var audioInputs: [NextLevelDevicePosition: AVAssetWriterInput] = [:]
    private var pixelBufferAdaptors: [NextLevelDevicePosition: AVAssetWriterInputPixelBufferAdaptor] = [:]
    
    private var combinedAssetWriter: AVAssetWriter?
    private var compositionAssetWriter: AVAssetWriter?
    private var compositor: NextLevelMultiCameraCompositor?
    
    private var startTime: CMTime?
    private var lastVideoTime: CMTime?
    private var recordingQueue: DispatchQueue
    
    private var recordingURLs: [NextLevelDevicePosition: URL] = [:]
    private var combinedRecordingURL: URL?
    
    // MARK: - object lifecycle
    
    public init(recordingMode: MultiCameraRecordingMode) {
        self.recordingMode = recordingMode
        self.recordingQueue = DispatchQueue(label: "engineering.NextLevel.MultiCameraRecording", qos: .userInitiated)
    }
    
    // MARK: - recording control
    
    /// Prepare recording with current configuration
    public func prepareRecording() throws {
        guard state == .idle else {
            throw MultiCameraRecordingError.recordingInProgress
        }
        
        guard let configuration = self.configuration else {
            throw MultiCameraRecordingError.invalidConfiguration
        }
        
        state = .preparing
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                switch self.recordingMode {
                case .separate:
                    try self.prepareSeparateRecording(configuration: configuration)
                case .combined:
                    try self.prepareCombinedRecording(configuration: configuration)
                case .composited:
                    try self.prepareCompositedRecording(configuration: configuration)
                }
                
                self.state = .idle
            } catch {
                print("NextLevel, failed to prepare recording: \(error)")
                self.state = .idle
            }
        }
    }
    
    /// Start recording
    public func startRecording() throws {
        guard state == .idle else {
            throw MultiCameraRecordingError.notReadyToRecord
        }
        
        state = .recording
        startTime = nil
        lastVideoTime = nil
    }
    
    /// Pause recording
    public func pauseRecording() {
        guard state == .recording else {
            return
        }
        
        state = .paused
    }
    
    /// Resume recording
    public func resumeRecording() {
        guard state == .paused else {
            return
        }
        
        state = .recording
    }
    
    /// Stop recording
    public func stopRecording(completion: @escaping ([URL]?, Error?) -> Void) {
        guard state == .recording || state == .paused else {
            completion(nil, MultiCameraRecordingError.noRecordingInProgress)
            return
        }
        
        state = .finishing
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.finishRecording { urls, error in
                self.state = .idle
                self.cleanup()
                
                DispatchQueue.main.async {
                    completion(urls, error)
                }
            }
        }
    }
    
    // MARK: - sample buffer processing
    
    /// Process video sample buffer from specific camera
    public func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition) {
        guard state == .recording else {
            return
        }
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Initialize start time
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if self.startTime == nil {
                self.startTime = timestamp
            }
            
            // Calculate relative time
            let relativeTime = CMTimeSubtract(timestamp, self.startTime!)
            
            switch self.recordingMode {
            case .separate:
                self.writeSeparateVideoFrame(sampleBuffer, position: position, time: relativeTime)
            case .combined:
                self.writeCombinedVideoFrame(sampleBuffer, position: position, time: relativeTime)
            case .composited:
                self.writeCompositedVideoFrame(sampleBuffer, position: position, time: relativeTime)
            }
            
            self.lastVideoTime = relativeTime
        }
    }
    
    /// Process audio sample buffer
    public func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition?) {
        guard state == .recording else {
            return
        }
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Initialize start time if needed
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if self.startTime == nil {
                self.startTime = timestamp
            }
            
            // Calculate relative time
            let relativeTime = CMTimeSubtract(timestamp, self.startTime!)
            
            // Write audio based on mode
            self.writeAudioFrame(sampleBuffer, position: position, time: relativeTime)
        }
    }
    
    // MARK: - private recording preparation
    
    private func prepareSeparateRecording(configuration: NextLevelMultiCameraConfiguration) throws {
        // Clean up any existing writers
        cleanup()
        
        // Create asset writer for each camera
        for position in configuration.enabledCameras {
            let fileName = generateFileName(for: position)
            let url = outputDirectory.appendingPathComponent(fileName)
            recordingURLs[position] = url
            
            // Create asset writer
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
                throw MultiCameraRecordingError.writerCreationFailed
            }
            
            // Add video input
            let videoInput = createVideoInput(for: position)
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
                videoInputs[position] = videoInput
                
                // Create pixel buffer adaptor
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes()
                )
                pixelBufferAdaptors[position] = adaptor
            }
            
            // Add audio input if this is the audio source
            if position == configuration.audioSource {
                let audioInput = createAudioInput()
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    audioInputs[position] = audioInput
                }
            }
            
            assetWriters[position] = writer
        }
    }
    
    private func prepareCombinedRecording(configuration: NextLevelMultiCameraConfiguration) throws {
        // Clean up any existing writers
        cleanup()
        
        // Create single asset writer with multiple tracks
        let fileName = generateFileName(for: nil)
        let url = outputDirectory.appendingPathComponent(fileName)
        combinedRecordingURL = url
        
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw MultiCameraRecordingError.writerCreationFailed
        }
        
        // Add video track for each camera
        for position in configuration.enabledCameras {
            let videoInput = createVideoInput(for: position)
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
                videoInputs[position] = videoInput
                
                // Create pixel buffer adaptor
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes()
                )
                pixelBufferAdaptors[position] = adaptor
            }
        }
        
        // Add single audio track
        let audioInput = createAudioInput()
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
            audioInputs[.unspecified] = audioInput
        }
        
        combinedAssetWriter = writer
    }
    
    private func prepareCompositedRecording(configuration: NextLevelMultiCameraConfiguration) throws {
        // Create compositor
        compositor = NextLevelMultiCameraCompositor(configuration: configuration)
        
        // Create single asset writer for composed output
        let fileName = generateFileName(for: nil, suffix: "_composed")
        let url = outputDirectory.appendingPathComponent(fileName)
        combinedRecordingURL = url
        
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw MultiCameraRecordingError.writerCreationFailed
        }
        
        // Add single video input for composed output
        let videoInput = createVideoInput(for: .unspecified, size: compositor?.outputSize ?? CGSize(width: 1920, height: 1080))
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
            videoInputs[.unspecified] = videoInput
            
            // Create pixel buffer adaptor
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: pixelBufferAttributes()
            )
            pixelBufferAdaptors[.unspecified] = adaptor
        }
        
        // Add audio input
        let audioInput = createAudioInput()
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
            audioInputs[.unspecified] = audioInput
        }
        
        compositionAssetWriter = writer
    }
    
    // MARK: - private helper methods
    
    private func createVideoInput(for position: NextLevelDevicePosition, size: CGSize? = nil) -> AVAssetWriterInput {
        let outputSize = size ?? CGSize(width: 1280, height: 720)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6000000,
                AVVideoExpectedSourceFrameRateKey: configuration?.preferredFrameRate ?? 30,
                AVVideoMaxKeyFrameIntervalKey: configuration?.preferredFrameRate ?? 30
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        
        // Add metadata to identify camera source
        var metadata = [AVMetadataItem]()
        if position != .unspecified {
            let item = AVMutableMetadataItem()
            item.key = "CameraPosition" as NSString
            item.value = "\(position.rawValue)" as NSString
            metadata.append(item)
        }
        input.metadata = metadata
        
        return input
    }
    
    private func createAudioInput() -> AVAssetWriterInput {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]
        
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        
        return input
    }
    
    private func pixelBufferAttributes() -> [String: Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280,
            kCVPixelBufferHeightKey as String: 720
        ]
    }
    
    private func generateFileName(for position: NextLevelDevicePosition?, suffix: String = "") -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        if let position = position {
            let positionString = position == .front ? "Front" : "Back"
            return "\(fileNamePrefix)_\(positionString)_\(timestamp)\(suffix).mp4"
        } else {
            return "\(fileNamePrefix)_\(timestamp)\(suffix).mp4"
        }
    }
    
    private func cleanup() {
        // Stop and release all writers
        for (_, writer) in assetWriters {
            if writer.status == .writing {
                writer.cancelWriting()
            }
        }
        
        combinedAssetWriter?.cancelWriting()
        compositionAssetWriter?.cancelWriting()
        
        // Clear all references
        assetWriters.removeAll()
        videoInputs.removeAll()
        audioInputs.removeAll()
        pixelBufferAdaptors.removeAll()
        recordingURLs.removeAll()
        
        combinedAssetWriter = nil
        compositionAssetWriter = nil
        combinedRecordingURL = nil
        compositor = nil
        
        startTime = nil
        lastVideoTime = nil
    }
    
    // MARK: - frame writing
    
    private func writeSeparateVideoFrame(_ sampleBuffer: CMSampleBuffer, position: NextLevelDevicePosition, time: CMTime) {
        guard let writer = assetWriters[position],
              let input = videoInputs[position] else {
            return
        }
        
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }
        
        if writer.status == .writing && input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
    
    private func writeCombinedVideoFrame(_ sampleBuffer: CMSampleBuffer, position: NextLevelDevicePosition, time: CMTime) {
        guard let writer = combinedAssetWriter,
              let input = videoInputs[position] else {
            return
        }
        
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }
        
        if writer.status == .writing && input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
    
    private func writeCompositedVideoFrame(_ sampleBuffer: CMSampleBuffer, position: NextLevelDevicePosition, time: CMTime) {
        // Store frames in compositor
        compositor?.addFrame(sampleBuffer, from: position, at: time)
        
        // Compose and write when we have frames from all cameras
        if let composedBuffer = compositor?.composeFrame(at: time) {
            writeComposedFrame(composedBuffer, time: time)
        }
    }
    
    private func writeComposedFrame(_ pixelBuffer: CVPixelBuffer, time: CMTime) {
        guard let writer = compositionAssetWriter,
              let input = videoInputs[.unspecified],
              let adaptor = pixelBufferAdaptors[.unspecified] else {
            return
        }
        
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }
        
        if writer.status == .writing && input.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }
    
    private func writeAudioFrame(_ sampleBuffer: CMSampleBuffer, position: NextLevelDevicePosition?, time: CMTime) {
        // Determine which audio input to use based on recording mode
        let audioInput: AVAssetWriterInput?
        let writer: AVAssetWriter?
        
        switch recordingMode {
        case .separate:
            if let pos = position {
                audioInput = audioInputs[pos]
                writer = assetWriters[pos]
            } else {
                // Default to primary camera position
                let pos = configuration?.primaryCameraPosition ?? .back
                audioInput = audioInputs[pos]
                writer = assetWriters[pos]
            }
        case .combined, .composited:
            audioInput = audioInputs[.unspecified]
            writer = combinedAssetWriter ?? compositionAssetWriter
        }
        
        guard let input = audioInput,
              let assetWriter = writer,
              input.isReadyForMoreMediaData else {
            return
        }
        
        if assetWriter.status == .writing {
            input.append(sampleBuffer)
        }
    }
    
    // MARK: - recording finalization
    
    private func finishRecording(completion: @escaping ([URL]?, Error?) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        var finalError: Error?
        
        // Finish separate recordings
        for (position, writer) in assetWriters {
            if writer.status == .writing {
                group.enter()
                writer.finishWriting {
                    if writer.status == .completed,
                       let url = self.recordingURLs[position] {
                        urls.append(url)
                    } else if let error = writer.error {
                        finalError = error
                    }
                    group.leave()
                }
            }
        }
        
        // Finish combined recording
        if let writer = combinedAssetWriter, writer.status == .writing {
            group.enter()
            writer.finishWriting {
                if writer.status == .completed,
                   let url = self.combinedRecordingURL {
                    urls.append(url)
                } else if let error = writer.error {
                    finalError = error
                }
                group.leave()
            }
        }
        
        // Finish composited recording
        if let writer = compositionAssetWriter, writer.status == .writing {
            group.enter()
            writer.finishWriting {
                if writer.status == .completed,
                   let url = self.combinedRecordingURL {
                    urls.append(url)
                } else if let error = writer.error {
                    finalError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: recordingQueue) {
            completion(urls.isEmpty ? nil : urls, finalError)
        }
    }
}

// MARK: - NextLevelMultiCameraCompositor

/// Simple compositor for multi-camera frames
private class NextLevelMultiCameraCompositor {
    
    let configuration: NextLevelMultiCameraConfiguration
    let outputSize: CGSize
    
    private var frameBuffers: [NextLevelDevicePosition: CVPixelBuffer] = [:]
    private var ciContext: CIContext
    
    init(configuration: NextLevelMultiCameraConfiguration) {
        self.configuration = configuration
        self.outputSize = CGSize(width: 1920, height: 1080)
        self.ciContext = CIContext()
    }
    
    func addFrame(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition, at time: CMTime) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            frameBuffers[position] = pixelBuffer
        }
    }
    
    func composeFrame(at time: CMTime) -> CVPixelBuffer? {
        // Simple picture-in-picture composition
        // This is a basic implementation - can be enhanced with more sophisticated composition
        
        guard let primaryBuffer = frameBuffers[configuration.primaryCameraPosition],
              let secondaryBuffer = frameBuffers[configuration.secondaryCameraPosition] else {
            return nil
        }
        
        // Create output pixel buffer
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return nil
        }
        
        // Compose using Core Image
        let primaryImage = CIImage(cvPixelBuffer: primaryBuffer)
        let secondaryImage = CIImage(cvPixelBuffer: secondaryBuffer)
        
        // Scale secondary image for PiP
        let secondaryScale: CGFloat = 0.25
        let scaledSecondary = secondaryImage.transformed(by: CGAffineTransform(scaleX: secondaryScale, y: secondaryScale))
        
        // Position secondary image in corner
        let xOffset = outputSize.width * 0.7
        let yOffset = outputSize.height * 0.05
        let positionedSecondary = scaledSecondary.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))
        
        // Composite images
        let composited = positionedSecondary.composited(over: primaryImage)
        
        // Render to output buffer
        ciContext.render(composited, to: output)
        
        return output
    }
}