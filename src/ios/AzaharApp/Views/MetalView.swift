// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import QuartzCore
import UIKit

/// A UIView that hosts a CAMetalLayer and drives the emulation present loop
/// via a CADisplayLink. This is the SwiftUI-side rendering surface.
struct MetalView: UIViewRepresentable {
    @ObservedObject var viewModel: EmulationViewModel

    func makeUIView(context: Context) -> MetalViewUIView {
        AppLogger.info("[MetalView] Creating MetalViewUIView")
        let view = MetalViewUIView(viewModel: viewModel)
        return view
    }

    func updateUIView(_ uiView: MetalViewUIView, context: Context) {
        uiView.viewModel = viewModel
    }
}

/// UIKit view backing the MetalView SwiftUI wrapper.
/// Creates a CAMetalLayer and hands it to the bridge.
final class MetalViewUIView: UIView {
    var viewModel: EmulationViewModel

    private var displayLink: CADisplayLink?
    private var isSurfaceSet = false

    init(viewModel: EmulationViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    private var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    private func setupLayer() {
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.drawableSize = bounds.size
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.drawableSize = bounds.size

        // Start presenting after first layout when we have valid dimensions
        if !isSurfaceSet && bounds.size.width > 0 && bounds.size.height > 0 {
            AppLogger.info("[MetalView] layoutSubviews with valid bounds: \(bounds) - calling startPresenting()")
            startPresenting()
        } else if isSurfaceSet {
            // Update existing surface with new dimensions
            let scale = Float(UIScreen.main.scale)
            az_emu_surface_set(Unmanaged.passUnretained(metalLayer).toOpaque(), scale)
            let portrait = bounds.height > bounds.width
            az_set_portrait_mode(portrait)
            az_update_framebuffer(portrait)
        }
    }

    func startPresenting() {
        guard displayLink == nil else { 
            AppLogger.debug("[MetalView] startPresenting() called but displayLink already exists")
            return 
        }

        AppLogger.info("[MetalView] Starting presentation - setting up Metal surface")
        AppLogger.debug("[MetalView] Bounds: \(bounds), Scale: \(UIScreen.main.scale)")
        
        let scale = Float(UIScreen.main.scale)
        az_emu_surface_set(Unmanaged.passUnretained(metalLayer).toOpaque(), scale)
        isSurfaceSet = true
        
        AppLogger.info("[MetalView] Metal surface set successfully!")

        let portrait = bounds.height > bounds.width
        az_set_portrait_mode(portrait)
        az_update_framebuffer(portrait)
        
        AppLogger.debug("[MetalView] Portrait mode: \(portrait)")

        // Add ManicEMU-style delay before starting render loop
        // This ensures Metal layer is fully initialized before rendering starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            AppLogger.info("[MetalView] Starting CADisplayLink after 1.0s delay (ManicEMU timing)")
            let link = CADisplayLink(target: self, selector: #selector(self.drawFrame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.displayLink = link
            
            AppLogger.info("[MetalView] CADisplayLink started - ready to render frames")
        }
    }

    func stopPresenting() {
        displayLink?.invalidate()
        displayLink = nil
        isSurfaceSet = false
    }

    @objc private func drawFrame() {
        if az_is_running() && !az_is_paused() {
            az_present_frame()
        }
    }

    deinit {
        stopPresenting()
        az_emu_surface_destroy()
    }
}
