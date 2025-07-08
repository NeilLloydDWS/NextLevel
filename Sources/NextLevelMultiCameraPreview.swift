//
//  NextLevelMultiCameraPreview.swift
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

// MARK: - NextLevelMultiCameraPreview

/// Multi-camera preview management for NextLevel
public class NextLevelMultiCameraPreview: UIView {
    
    // MARK: - properties
    
    /// Preview layers indexed by camera position
    public var previewLayers: [NextLevelDevicePosition: AVCaptureVideoPreviewLayer] = [:]
    
    /// Primary preview layer (convenience accessor)
    public var primaryPreviewLayer: AVCaptureVideoPreviewLayer? {
        return previewLayers[configuration?.primaryCameraPosition ?? .back]
    }
    
    /// Secondary preview layer (convenience accessor)
    public var secondaryPreviewLayer: AVCaptureVideoPreviewLayer? {
        return previewLayers[configuration?.secondaryCameraPosition ?? .front]
    }
    
    /// Current layout mode
    public var layout: MultiCameraPreviewLayout = .pictureInPicture(
        primaryRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        secondaryRect: CGRect(x: 0.65, y: 0.02, width: 0.33, height: 0.25)
    ) {
        didSet {
            setNeedsLayout()
        }
    }
    
    /// Multi-camera configuration reference
    public weak var configuration: NextLevelMultiCameraConfiguration?
    
    /// Capture session reference
    public weak var session: AVCaptureSession? {
        didSet {
            updatePreviewLayers()
        }
    }
    
    /// Animation duration for layout changes
    public var layoutAnimationDuration: TimeInterval = 0.3
    
    /// Enable/disable animations
    public var animationsEnabled: Bool = true
    
    /// Video gravity for individual preview layers
    public var videoGravityPerCamera: [NextLevelDevicePosition: AVLayerVideoGravity] = [:] {
        didSet {
            updateVideoGravity()
        }
    }
    
    /// Corner radius for preview layers
    public var previewCornerRadius: CGFloat = 12.0 {
        didSet {
            updatePreviewLayerProperties()
        }
    }
    
    /// Border width for secondary preview in PiP mode
    public var secondaryPreviewBorderWidth: CGFloat = 2.0 {
        didSet {
            updatePreviewLayerProperties()
        }
    }
    
    /// Border color for secondary preview in PiP mode
    public var secondaryPreviewBorderColor: UIColor = .white {
        didSet {
            updatePreviewLayerProperties()
        }
    }
    
    // MARK: - object lifecycle
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }
    
    private func commonInit() {
        self.backgroundColor = .black
        self.clipsToBounds = true
    }
    
    // MARK: - layout
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard self.configuration != nil else {
            return
        }
        
        let animationBlock = {
            // Layout based on current mode
            switch self.layout {
            case .pictureInPicture(let primaryRect, let secondaryRect):
                self.layoutPictureInPicture(primaryRect: primaryRect, secondaryRect: secondaryRect)
                
            case .sideBySide(let splitRatio):
                self.layoutSideBySide(splitRatio: splitRatio)
                
            case .topBottom(let splitRatio):
                self.layoutTopBottom(splitRatio: splitRatio)
                
            case .custom(let layoutProvider):
                self.layoutCustom(layoutProvider: layoutProvider)
            }
        }
        
        if animationsEnabled {
            UIView.animate(withDuration: layoutAnimationDuration, 
                          delay: 0,
                          options: [.curveEaseInOut],
                          animations: animationBlock)
        } else {
            animationBlock()
        }
    }
    
    // MARK: - preview management
    
    /// Create or update preview layers based on configuration
    public func updatePreviewLayers() {
        guard let configuration = self.configuration,
              let session = self.session else {
            return
        }
        
        // Remove preview layers for disabled cameras
        for (position, layer) in previewLayers {
            if !configuration.enabledCameras.contains(position) {
                layer.removeFromSuperlayer()
                previewLayers.removeValue(forKey: position)
            }
        }
        
        // Create preview layers for enabled cameras
        for position in configuration.enabledCameras {
            if previewLayers[position] == nil {
                let previewLayer = createPreviewLayer(for: position)
                previewLayer.session = session
                self.layer.addSublayer(previewLayer)
                previewLayers[position] = previewLayer
            }
        }
        
        // Update z-order
        updateLayerHierarchy()
        
        setNeedsLayout()
    }
    
    /// Create a preview layer for a specific camera position
    private func createPreviewLayer(for position: NextLevelDevicePosition) -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = videoGravityPerCamera[position] ?? .resizeAspectFill
        previewLayer.masksToBounds = true
        
        // Configure based on position
        if position == configuration?.secondaryCameraPosition {
            previewLayer.cornerRadius = previewCornerRadius
            previewLayer.borderWidth = secondaryPreviewBorderWidth
            previewLayer.borderColor = secondaryPreviewBorderColor.cgColor
        }
        
        return previewLayer
    }
    
    /// Update preview layer visual properties
    private func updatePreviewLayerProperties() {
        for (position, layer) in previewLayers {
            if position == configuration?.secondaryCameraPosition {
                layer.cornerRadius = previewCornerRadius
                layer.borderWidth = secondaryPreviewBorderWidth
                layer.borderColor = secondaryPreviewBorderColor.cgColor
            } else {
                layer.cornerRadius = 0
                layer.borderWidth = 0
            }
        }
    }
    
    /// Update layer hierarchy to ensure correct z-ordering
    private func updateLayerHierarchy() {
        // Ensure primary is behind secondary for PiP
        if let primary = primaryPreviewLayer {
            self.layer.insertSublayer(primary, at: 0)
        }
        
        if let secondary = secondaryPreviewLayer {
            self.layer.addSublayer(secondary)
        }
    }
    
    // MARK: - layout implementations
    
    private func layoutPictureInPicture(primaryRect: CGRect, secondaryRect: CGRect) {
        let bounds = self.bounds
        
        // Layout primary (full screen)
        primaryPreviewLayer?.frame = CGRect(
            x: primaryRect.origin.x * bounds.width,
            y: primaryRect.origin.y * bounds.height,
            width: primaryRect.width * bounds.width,
            height: primaryRect.height * bounds.height
        )
        
        // Layout secondary (small overlay)
        secondaryPreviewLayer?.frame = CGRect(
            x: secondaryRect.origin.x * bounds.width,
            y: secondaryRect.origin.y * bounds.height,
            width: secondaryRect.width * bounds.width,
            height: secondaryRect.height * bounds.height
        )
    }
    
    private func layoutSideBySide(splitRatio: CGFloat) {
        let bounds = self.bounds
        let primaryWidth = bounds.width * splitRatio
        
        primaryPreviewLayer?.frame = CGRect(
            x: 0,
            y: 0,
            width: primaryWidth,
            height: bounds.height
        )
        
        secondaryPreviewLayer?.frame = CGRect(
            x: primaryWidth,
            y: 0,
            width: bounds.width - primaryWidth,
            height: bounds.height
        )
    }
    
    private func layoutTopBottom(splitRatio: CGFloat) {
        let bounds = self.bounds
        let primaryHeight = bounds.height * splitRatio
        
        primaryPreviewLayer?.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: primaryHeight
        )
        
        secondaryPreviewLayer?.frame = CGRect(
            x: 0,
            y: primaryHeight,
            width: bounds.width,
            height: bounds.height - primaryHeight
        )
    }
    
    private func layoutCustom(layoutProvider: (CGSize) -> [NextLevelDevicePosition: CGRect]) {
        let rects = layoutProvider(self.bounds.size)
        
        for (position, rect) in rects {
            previewLayers[position]?.frame = rect
        }
    }
    
    // MARK: - interaction
    
    /// Switch primary and secondary camera positions
    public func switchCameras(animated: Bool = true) {
        guard let configuration = self.configuration else {
            return
        }
        
        // Swap positions in configuration
        let temp = configuration.primaryCameraPosition
        configuration.primaryCameraPosition = configuration.secondaryCameraPosition
        configuration.secondaryCameraPosition = temp
        
        // Update properties and layout
        updatePreviewLayerProperties()
        updateLayerHierarchy()
        
        if animated {
            setNeedsLayout()
        } else {
            let wasEnabled = animationsEnabled
            animationsEnabled = false
            setNeedsLayout()
            layoutIfNeeded()
            animationsEnabled = wasEnabled
        }
    }
    
    /// Get the camera position at a specific point
    public func cameraPosition(at point: CGPoint) -> NextLevelDevicePosition? {
        // Check layers in reverse order (top to bottom)
        for (position, layer) in previewLayers.reversed() {
            if layer.frame.contains(point) && !layer.isHidden {
                return position
            }
        }
        return nil
    }
    
    /// Focus at point for specific camera
    public func focus(at point: CGPoint, for position: NextLevelDevicePosition) {
        guard let layer = previewLayers[position] else {
            return
        }
        
        // Convert point to layer coordinates
        let layerPoint = self.layer.convert(point, to: layer)
        
        // Normalize to 0-1 range
        _ = CGPoint(
            x: layerPoint.x / layer.bounds.width,
            y: layerPoint.y / layer.bounds.height
        )
        
        // TODO: Trigger focus through NextLevel
        // This would require adding a method to NextLevel to focus a specific camera
    }
    
    // MARK: - individual preview layer access
    
    /// Get preview layer for specific camera position
    public func previewLayer(for position: NextLevelDevicePosition) -> AVCaptureVideoPreviewLayer? {
        return previewLayers[position]
    }
    
    /// Get all active preview layers
    public func allPreviewLayers() -> [AVCaptureVideoPreviewLayer] {
        return Array(previewLayers.values)
    }
    
    /// Create a detached preview layer for embedding in custom views
    public func createDetachedPreviewLayer(for position: NextLevelDevicePosition) -> AVCaptureVideoPreviewLayer? {
        guard configuration?.enabledCameras.contains(position) == true,
              let session = self.session else {
            return nil
        }
        
        let detachedLayer = AVCaptureVideoPreviewLayer(session: session)
        detachedLayer.videoGravity = videoGravityPerCamera[position] ?? .resizeAspectFill
        detachedLayer.masksToBounds = true
        
        // Note: This creates a new preview layer that shares the same session
        // The caller is responsible for managing this layer's lifecycle
        return detachedLayer
    }
    
    /// Enable or disable a specific preview layer
    public func setPreviewEnabled(_ enabled: Bool, for position: NextLevelDevicePosition) {
        previewLayers[position]?.isHidden = !enabled
    }
    
    /// Update video gravity for all preview layers
    private func updateVideoGravity() {
        for (position, layer) in previewLayers {
            if let gravity = videoGravityPerCamera[position] {
                layer.videoGravity = gravity
            }
        }
    }
    
    /// Configure individual preview layer properties
    public func configurePreviewLayer(for position: NextLevelDevicePosition,
                                    cornerRadius: CGFloat? = nil,
                                    borderWidth: CGFloat? = nil,
                                    borderColor: UIColor? = nil,
                                    videoGravity: AVLayerVideoGravity? = nil) {
        guard let layer = previewLayers[position] else { return }
        
        if let cornerRadius = cornerRadius {
            layer.cornerRadius = cornerRadius
        }
        if let borderWidth = borderWidth {
            layer.borderWidth = borderWidth
        }
        if let borderColor = borderColor {
            layer.borderColor = borderColor.cgColor
        }
        if let videoGravity = videoGravity {
            layer.videoGravity = videoGravity
            videoGravityPerCamera[position] = videoGravity
        }
    }
}