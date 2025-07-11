//
//  NextLevel+AVFoundation.swift
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

extension AVCaptureConnection {

    /// Returns the capture connection for the desired media type, otherwise nil.
    ///
    /// - Parameters:
    ///   - mediaType: Specified media type. (i.e. AVMediaTypeVideo, AVMediaTypeAudio, etc.)
    ///   - connections: Array of `AVCaptureConnection` objects to search
    /// - Returns: Capture connection for the desired media type, otherwise nil
    public class func connection(withMediaType mediaType: AVMediaType, fromConnections connections: [AVCaptureConnection]) -> AVCaptureConnection? {
        for connection: AVCaptureConnection in connections {
            for port: AVCaptureInput.Port in connection.inputPorts {
                if port.mediaType == mediaType {
                    return connection
                }
            }
        }
        return nil
    }

}

extension AVCaptureDeviceInput {

    /// Returns the capture device input for the desired media type and capture session, otherwise nil.
    ///
    /// - Parameters:
    ///   - mediaType: Specified media type. (i.e. AVMediaTypeVideo, AVMediaTypeAudio, etc.)
    ///   - captureSession: Capture session for which to query
    /// - Returns: Desired capture device input for the associated media type, otherwise nil
    public class func deviceInput(withMediaType mediaType: AVMediaType, captureSession: AVCaptureSession) -> AVCaptureDeviceInput? {
        if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
            for deviceInput in inputs {
                if deviceInput.device.hasMediaType(mediaType) {
                    return deviceInput
                }
            }
        }
        return nil
    }

}

extension AVCaptureDevice {

    // MARK: - device lookup

    /// Returns the capture device for the desired device type and position.
    /// #protip, NextLevelDevicePosition.avfoundationType can provide the AVFoundation type.
    ///
    /// - Parameters:
    ///   - deviceType: Specified capture device type, (i.e. builtInMicrophone, builtInWideAngleCamera, etc.)
    ///   - position: Desired position of device
    /// - Returns: Capture device for the specified type and position, otherwise nil
    public class func captureDevice(withType deviceType: AVCaptureDevice.DeviceType, forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [deviceType]
        if let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: position).devices.first {
            return discoverySession
        }
        return nil
    }

    /// Returns the default wide angle video device for the desired position, otherwise nil.
    ///
    /// - Parameter position: Desired position of the device
    /// - Returns: Wide angle video capture device, otherwise nil
    public class func wideAngleVideoDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [AVCaptureDevice.DeviceType.builtInWideAngleCamera]
        if let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: position).devices.first {
            return discoverySession
        }
        return nil
    }

    /// Returns the default telephoto video device for the desired position, otherwise nil.
    ///
    /// - Parameter position: Desired position of the device
    /// - Returns: Telephoto video capture device, otherwise nil
    public class func telephotoVideoDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [AVCaptureDevice.DeviceType.builtInTelephotoCamera]
        if let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: position).devices.first {
            return discoverySession
        }
        return nil
    }

	/// Returns the first available camera device of specified types.
	///
	/// - Parameters:
	///   - position: Desired position of the device
	///   - prioritizedDeviceTypes: Device types of interest, in descending order
	/// - Returns: Primary video capture device found, otherwise nil
	public class func primaryVideoDevice(forPosition position: AVCaptureDevice.Position, prioritizedDeviceTypes: [AVCaptureDevice.DeviceType] = [/* .builtInTripleCamera,*/ .builtInDualCamera, .builtInWideAngleCamera]) -> AVCaptureDevice? {
		AVCaptureDevice.DiscoverySession(deviceTypes: prioritizedDeviceTypes, mediaType: AVMediaType.video, position: position).devices.first
	}

    /// Returns the default video capture device, otherwise nil.
    ///
    /// - Returns: Default video capture device, otherwise nil
    public class func videoDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: AVMediaType.video)
    }

    /// Returns the default audio capture device, otherwise nil.
    ///
    /// - Returns: default audio capture device, otherwise nil
    public class func audioDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: AVMediaType.audio)
    }

    // MARK: - utilities

    /// Calculates focal length and principle point camera intrinsic parameters for OpenCV.
    /// (see Hartley's Mutiple View Geometry, Chapter 6)
    ///
    /// - Parameters:
    ///   - focalLengthX: focal length along the x-axis
    ///   - focalLengthY: focal length along the y-axis
    ///   - principlePointX: principle point x-coordinate
    ///   - principlePointY: principle point y-coordinate
    /// - Returns: `true` when the focal length and principle point parameters are successfully calculated.
    public func focalLengthAndPrinciplePoint(focalLengthX: inout Float, focalLengthY: inout Float, principlePointX: inout Float, principlePointY: inout Float) {
        let dimensions = CMVideoFormatDescriptionGetPresentationDimensions(self.activeFormat.formatDescription, usePixelAspectRatio: true, useCleanAperture: true)

        principlePointX = Float(dimensions.width) * 0.5
        principlePointY = Float(dimensions.height) * 0.5

        let horizontalFieldOfView = self.activeFormat.videoFieldOfView
        let verticalFieldOfView = (horizontalFieldOfView / principlePointX) * principlePointY

        focalLengthX = abs( Float(dimensions.width) / (2.0 * tan(horizontalFieldOfView / 180.0 * .pi / 2 )) )
        focalLengthY = abs( Float(dimensions.height) / (2.0 * tan(verticalFieldOfView / 180.0 * .pi / 2 )) )
    }
    
    // MARK: - multi-camera support
    
    /// Returns all available capture devices for multi-camera session
    ///
    /// - Returns: Array of devices that support multi-camera capture
    public class func multiCameraDevices() -> [AVCaptureDevice] {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            return []
        }
        
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInUltraWideCamera
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        return discoverySession.devices.filter { device in
            // Check if device supports multi-camera by checking a format
            if let format = device.formats.first(where: { $0.isMultiCamSupported }) {
                return format.isMultiCamSupported
            }
            return false
        }
    }
    
    /// Checks if a specific device supports multi-camera capture
    ///
    /// - Returns: true if the device has at least one format that supports multi-camera
    public var supportsMultiCamera: Bool {
        return self.formats.contains { $0.isMultiCamSupported }
    }
    
    /// Returns the best format for multi-camera capture
    ///
    /// - Returns: Best format that supports multi-camera, preferring lower resolutions for performance
    public var bestMultiCameraFormat: AVCaptureDevice.Format? {
        let multiCamFormats = self.formats.filter { $0.isMultiCamSupported }
        
        // Sort by resolution (prefer lower resolutions for better performance)
        return multiCamFormats.sorted { format1, format2 in
            let dims1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription)
            let dims2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription)
            let pixels1 = Int(dims1.width) * Int(dims1.height)
            let pixels2 = Int(dims2.width) * Int(dims2.height)
            return pixels1 < pixels2
        }.first
    }

}

extension AVCaptureDevice.Format {

    /// Returns the maximum capable framerate for the desired capture format and minimum, otherwise zero.
    ///
    /// - Parameters:
    ///   - format: Capture format to evaluate for a specific framerate.
    ///   - minFrameRate: Lower bound time scale or minimum desired framerate.
    /// - Returns: Maximum capable framerate within the desired format and minimum constraints.
    public class func maxFrameRate(forFormat format: AVCaptureDevice.Format, minFrameRate: CMTimeScale) -> CMTimeScale {
        var lowestTimeScale: CMTimeScale = 0
        for range in format.videoSupportedFrameRateRanges {
            if range.minFrameDuration.timescale >= minFrameRate && (lowestTimeScale == 0 || range.minFrameDuration.timescale < lowestTimeScale) {
                lowestTimeScale = range.minFrameDuration.timescale
            }
        }
        return lowestTimeScale
    }

    /// Checks if the specified capture device format supports a desired framerate and dimensions.
    ///
    /// - Parameters:
    ///   - frameRate: Desired frame rate
    ///   - dimensions: Desired video dimensions
    /// - Returns: `true` if the capture device format supports the given criteria, otherwise false
    public func isSupported(withFrameRate frameRate: CMTimeScale, dimensions: CMVideoDimensions = CMVideoDimensions(width: 0, height: 0)) -> Bool {
        let formatDimensions = CMVideoFormatDescriptionGetDimensions(self.formatDescription)
        if formatDimensions.width >= dimensions.width && formatDimensions.height >= dimensions.height {
            for frameRateRange in self.videoSupportedFrameRateRanges {
                if frameRateRange.minFrameDuration.timescale >= frameRate && frameRateRange.maxFrameDuration.timescale <= frameRate {
                    return true
                }
            }
        }
        return false
    }

}

extension AVCaptureDevice.Position {

    /// Checks if a camera device is available for a position.
    ///
    /// - Parameter devicePosition: Camera device position to query.
    /// - Returns: `true` if the camera device exists, otherwise false.
    public var isCameraDevicePositionAvailable: Bool {
        UIImagePickerController.isCameraDeviceAvailable(self.uikitType)
    }

    /// UIKit device equivalent type
    public var uikitType: UIImagePickerController.CameraDevice {
        switch self {
        case .front:
            return .front
        case .unspecified:
            fallthrough
        case .back:
            fallthrough
        @unknown default:
            return .rear
        }
    }

}

extension AVCaptureDevice.WhiteBalanceGains {

    /// Normalize gain values for a capture device.
    ///
    /// - Parameter captureDevice: Device used for adjustment.
    /// - Returns: Normalized gains.
    public func normalize(_ captureDevice: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        var newGains = self

        newGains.redGain = Swift.min(captureDevice.maxWhiteBalanceGain, Swift.max(1.0, newGains.redGain))
        newGains.greenGain = Swift.min(captureDevice.maxWhiteBalanceGain, Swift.max(1.0, newGains.greenGain))
        newGains.blueGain = Swift.min(captureDevice.maxWhiteBalanceGain, Swift.max(1.0, newGains.blueGain))

        return newGains
    }

}

extension AVCaptureVideoOrientation {

    /// UIKit orientation equivalent type
    public var uikitType: UIDeviceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        @unknown default:
            return .unknown
        }
    }

    internal static func avorientationFromUIDeviceOrientation(_ orientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        var avorientation: AVCaptureVideoOrientation = .portrait
        switch orientation {
        case .portrait:
            break
        case .landscapeLeft:
            avorientation = .landscapeRight
            break
        case .landscapeRight:
            avorientation = .landscapeLeft
            break
        case .portraitUpsideDown:
            avorientation = .portraitUpsideDown
            break
        default:
            break
        }
        return avorientation
    }

}
