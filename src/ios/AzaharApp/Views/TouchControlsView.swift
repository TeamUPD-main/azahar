// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// On-screen touch controls overlay using PNG assets from Android
/// Positions match the Android InputOverlay layout
struct TouchControlsView: View {
    @ObservedObject var viewModel: EmulationViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let isLandscape = w > h
            
            // Android uses 1000-based coordinates, we convert to percentages
            // Landscape reference: 1000x1000 grid
            // Portrait reference: 1000x1000 grid
            
            ZStack {
                if isLandscape {
                    landscapeControls(width: w, height: h)
                } else {
                    portraitControls(width: w, height: h)
                }
            }
        }
        .allowsHitTesting(viewModel.isControlsVisible)
    }
    
    private func landscapeControls(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // D-Pad (left side) - Position: (15, 470) out of 1000
            DPadView()
                .position(x: width * 0.015 + 60, y: height * 0.470 + 60)
            
            // Left Analog Stick - Position: (100, 670) out of 1000
            AnalogStickView(
                position: $viewModel.leftStickPosition,
                onPositionChanged: { x, y in
                    let nx = Float(x / 30)
                    let ny = Float(y / 30)
                    az_analog_event(Int32(AZ_STICK_LEFT), nx, ny)
                }
            )
            .position(x: width * 0.100, y: height * 0.670)
            
            // Right Analog Stick (C-Stick) - Position: (740, 770) out of 1000
            AnalogStickView(
                position: $viewModel.rightStickPosition,
                onPositionChanged: { x, y in
                    let nx = Float(x / 30)
                    let ny = Float(y / 30)
                    az_analog_event(Int32(AZ_STICK_C), nx, ny)
                }
            )
            .position(x: width * 0.740, y: height * 0.770)
            
            // Face buttons (A/B/X/Y) - Right side
            // Button A - Position: (930, 620)
            ButtonImage(name: "button_a", button: Int32(AZ_BUTTON_A))
                .position(x: width * 0.930, y: height * 0.620)
            
            // Button B - Position: (870, 720)
            ButtonImage(name: "button_b", button: Int32(AZ_BUTTON_B))
                .position(x: width * 0.870, y: height * 0.720)
            
            // Button X - Position: (870, 520)
            ButtonImage(name: "button_x", button: Int32(AZ_BUTTON_X))
                .position(x: width * 0.870, y: height * 0.520)
            
            // Button Y - Position: (810, 620)
            ButtonImage(name: "button_y", button: Int32(AZ_BUTTON_Y))
                .position(x: width * 0.810, y: height * 0.620)
            
            // L Trigger - Position: (13, 0)
            ButtonImage(name: "button_l", button: Int32(AZ_TRIGGER_L))
                .position(x: width * 0.013 + 40, y: height * 0.05)
            
            // R Trigger - Position: (895, 0)
            ButtonImage(name: "button_r", button: Int32(AZ_TRIGGER_R))
                .position(x: width * 0.895 + 40, y: height * 0.05)
            
            // ZL Trigger - Position: (13, 110)
            ButtonImage(name: "button_zl", button: Int32(AZ_BUTTON_ZL))
                .position(x: width * 0.013 + 40, y: height * 0.110 + 30)
            
            // ZR Trigger - Position: (895, 110)
            ButtonImage(name: "button_zr", button: Int32(AZ_BUTTON_ZR))
                .position(x: width * 0.895 + 40, y: height * 0.110 + 30)
            
            // Center buttons
            HStack(spacing: 12) {
                // Select - Position: (470, 850)
                ButtonImage(name: "button_select", button: Int32(AZ_BUTTON_SELECT))
                
                // Start - Position: (550, 850)
                ButtonImage(name: "button_start", button: Int32(AZ_BUTTON_START))
            }
            .position(x: width * 0.510, y: height * 0.850)
        }
    }
    
    private func portraitControls(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // D-Pad (left side) - Portrait Position: (10, 730)
            DPadView()
                .position(x: width * 0.010 + 60, y: height * 0.730)
            
            // Left Analog Stick - Portrait Position: (80, 850)
            AnalogStickView(
                position: $viewModel.leftStickPosition,
                onPositionChanged: { x, y in
                    let nx = Float(x / 30)
                    let ny = Float(y / 30)
                    az_analog_event(Int32(AZ_STICK_LEFT), nx, ny)
                }
            )
            .position(x: width * 0.080, y: height * 0.850)
            
            // Right Analog Stick (C-Stick) - Portrait Position: (800, 720)
            AnalogStickView(
                position: $viewModel.rightStickPosition,
                onPositionChanged: { x, y in
                    let nx = Float(x / 30)
                    let ny = Float(y / 30)
                    az_analog_event(Int32(AZ_STICK_C), nx, ny)
                }
            )
            .position(x: width * 0.800, y: height * 0.720)
            
            // Face buttons - Portrait positions
            // Button A - Portrait: (810, 870)
            ButtonImage(name: "button_a", button: Int32(AZ_BUTTON_A))
                .position(x: width * 0.810, y: height * 0.870)
            
            // Button B - Portrait: (710, 925)
            ButtonImage(name: "button_b", button: Int32(AZ_BUTTON_B))
                .position(x: width * 0.710, y: height * 0.925)
            
            // Button X - Portrait: (710, 815)
            ButtonImage(name: "button_x", button: Int32(AZ_BUTTON_X))
                .position(x: width * 0.710, y: height * 0.815)
            
            // Button Y - Portrait: (610, 870)
            ButtonImage(name: "button_y", button: Int32(AZ_BUTTON_Y))
                .position(x: width * 0.610, y: height * 0.870)
            
            // L Trigger - Portrait: (10, 640)
            ButtonImage(name: "button_l", button: Int32(AZ_TRIGGER_L))
                .position(x: width * 0.010 + 40, y: height * 0.640)
            
            // R Trigger - Portrait: (810, 640)
            ButtonImage(name: "button_r", button: Int32(AZ_TRIGGER_R))
                .position(x: width * 0.810 + 40, y: height * 0.640)
            
            // ZL Trigger - Portrait: (210, 640)
            ButtonImage(name: "button_zl", button: Int32(AZ_BUTTON_ZL))
                .position(x: width * 0.210, y: height * 0.640)
            
            // ZR Trigger - Portrait: (610, 640)
            ButtonImage(name: "button_zr", button: Int32(AZ_BUTTON_ZR))
                .position(x: width * 0.610, y: height * 0.640)
            
            // Center buttons - Portrait
            HStack(spacing: 12) {
                // Select - Portrait: (400, 794)
                ButtonImage(name: "button_select", button: Int32(AZ_BUTTON_SELECT))
                
                // Start - Portrait: (520, 794)
                ButtonImage(name: "button_start", button: Int32(AZ_BUTTON_START))
            }
            .position(x: width * 0.460, y: height * 0.794)
        }
    }
}

/// Button using PNG image assets
struct ButtonImage: View {
    let name: String
    let button: Int32
    @State private var isPressed = false
    
    var body: some View {
        Image(isPressed ? "\(name)_pressed" : name, bundle: .main)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 70, height: 70)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            az_button_event(button, true)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        az_button_event(button, false)
                    }
            )
    }
}

/// Virtual D-Pad using PNG assets
struct DPadView: View {
    @State private var currentDirection: Set<DPadDirection> = []
    
    var body: some View {
        ZStack {
            // Base dpad image
            Image(currentDirection.isEmpty ? "dpad" : 
                  currentDirection.count == 2 ? "dpad_pressed_two_directions" : 
                  "dpad_pressed_one_direction", bundle: .main)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
            
            // Invisible hit zones for each direction
            DPadHitZone(direction: .up, currentDirection: $currentDirection)
                .frame(width: 40, height: 40)
                .offset(y: -40)
            
            DPadHitZone(direction: .down, currentDirection: $currentDirection)
                .frame(width: 40, height: 40)
                .offset(y: 40)
            
            DPadHitZone(direction: .left, currentDirection: $currentDirection)
                .frame(width: 40, height: 40)
                .offset(x: -40)
            
            DPadHitZone(direction: .right, currentDirection: $currentDirection)
                .frame(width: 40, height: 40)
                .offset(x: 40)
        }
        .frame(width: 120, height: 120)
    }
}

enum DPadDirection: Hashable {
    case up, down, left, right
    
    var button: Int32 {
        switch self {
        case .up: return Int32(AZ_DPAD_UP)
        case .down: return Int32(AZ_DPAD_DOWN)
        case .left: return Int32(AZ_DPAD_LEFT)
        case .right: return Int32(AZ_DPAD_RIGHT)
        }
    }
}

struct DPadHitZone: View {
    let direction: DPadDirection
    @Binding var currentDirection: Set<DPadDirection>
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !currentDirection.contains(direction) {
                            currentDirection.insert(direction)
                            az_button_event(direction.button, true)
                        }
                    }
                    .onEnded { _ in
                        currentDirection.remove(direction)
                        az_button_event(direction.button, false)
                    }
            )
    }
}

/// Virtual analog stick (circle-pad style)
struct AnalogStickView: View {
    @Binding var position: CGPoint
    let onPositionChanged: (CGFloat, CGFloat) -> Void
    
    @State private var isDragging = false
    
    private let baseSize: CGFloat = 100
    private let knobSize: CGFloat = 50
    private let maxRadius: CGFloat = 25
    
    var body: some View {
        ZStack {
            // Base circle
            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: baseSize, height: baseSize)
            
            // Knob
            Circle()
                .fill(.white.opacity(0.6))
                .frame(width: knobSize, height: knobSize)
                .offset(x: position.x, y: position.y)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let distance = sqrt(dx * dx + dy * dy)
                    let clampedDistance = min(distance, maxRadius)
                    let angle = atan2(dy, dx)
                    let x = clampedDistance * cos(angle)
                    let y = clampedDistance * sin(angle)
                    position = CGPoint(x: x, y: y)
                    onPositionChanged(x, y)
                }
                .onEnded { _ in
                    position = .zero
                    onPositionChanged(0, 0)
                }
        )
    }
}
