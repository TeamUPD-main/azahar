// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// On-screen touch controls overlay (equivalent to Android's InputOverlay).
/// Renders virtual buttons (A/B/X/Y, D-Pad, L/R triggers, analog sticks, Start/Select)
/// and dispatches input events to the bridge.
struct TouchControlsView: View {
    @ObservedObject var viewModel: EmulationViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let isLandscape = w > h
            let scale = isLandscape ? min(w / 800, h / 400) : min(w / 400, h / 800)

            ZStack {
                // Analog sticks
                AnalogStickView(
                    position: $viewModel.leftStickPosition,
                    label: "L",
                    frameSize: CGSize(width: 60 * scale, height: 60 * scale),
                    center: CGPoint(x: 80 * scale, y: h - 90 * scale),
                    onPositionChanged: { x, y in
                        let nx = Float(x / (30 * scale))
                        let ny = Float(y / (30 * scale))
                        az_analog_event(Int32(AZ_STICK_LEFT), nx, ny)
                    }
                )

                AnalogStickView(
                    position: $viewModel.rightStickPosition,
                    label: "R",
                    frameSize: CGSize(width: 60 * scale, height: 60 * scale),
                    center: CGPoint(x: w - 80 * scale, y: h - 90 * scale),
                    onPositionChanged: { x, y in
                        let nx = Float(x / (30 * scale))
                        let ny = Float(y / (30 * scale))
                        az_analog_event(Int32(AZ_STICK_C), nx, ny)
                    }
                )

                // D-Pad (left side)
                DPadView(scale: scale, center: CGPoint(x: 80 * scale, y: h - 250 * scale))
                    .position(x: 80 * scale, y: h - 250 * scale)

                // Face buttons (right side)
                FaceButtonsView(scale: scale)
                    .position(x: w - 80 * scale, y: h - 250 * scale)

                // L/R triggers
                TriggerButton(label: "L", button: AZ_TRIGGER_L, scale: scale)
                    .position(x: 40 * scale, y: 30 * scale)
                TriggerButton(label: "R", button: AZ_TRIGGER_R, scale: scale)
                    .position(x: w - 40 * scale, y: 30 * scale)

                // Center buttons (Start, Select, Home)
                HStack(spacing: 20 * scale) {
                    SmallButton(label: "SEL", button: AZ_BUTTON_SELECT, scale: scale)
                    SmallButton(label: "START", button: AZ_BUTTON_START, scale: scale)
                }
                .position(x: w / 2, y: h - 40 * scale)
            }
        }
        .allowsHitTesting(viewModel.isControlsVisible)
    }
}

/// Virtual D-Pad.
struct DPadView: View {
    let scale: CGFloat
    let center: CGPoint

    private let directionSize: CGFloat = 32

    var body: some View {
        ZStack {
            // Center circle
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 28 * scale, height: 28 * scale)

            // Up
            DPadButton(direction: .up, size: directionSize * scale) {
                az_button_event(Int32(AZ_DPAD_UP), true)
            }
            .position(x: 0, y: -24 * scale)

            // Down
            DPadButton(direction: .down, size: directionSize * scale) {
                az_button_event(Int32(AZ_DPAD_DOWN), true)
            }
            .position(x: 0, y: 24 * scale)

            // Left
            DPadButton(direction: .left, size: directionSize * scale) {
                az_button_event(Int32(AZ_DPAD_LEFT), true)
            }
            .position(x: -24 * scale, y: 0)

            // Right
            DPadButton(direction: .right, size: directionSize * scale) {
                az_button_event(Int32(AZ_DPAD_RIGHT), true)
            }
            .position(x: 24 * scale, y: 0)
        }
        .frame(width: 80 * scale, height: 80 * scale)
    }
}

enum DPadDirection {
    case up, down, left, right

    var rotation: Angle {
        switch self {
        case .up:    return .zero
        case .right: return .degrees(90)
        case .down:  return .degrees(180)
        case .left:  return .degrees(-90)
        }
    }
}

struct DPadButton: View {
    let direction: DPadDirection
    let size: CGFloat
    let onPress: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onPress) {
            Triangle()
                .fill(isPressed ? .white : .white.opacity(0.5))
                .frame(width: size, height: size)
                .rotationEffect(direction.rotation)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
            if pressing { onPress() }
        }, perform: {})
    }
}

/// Simple equilateral triangle shape.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Face buttons (A, B, X, Y) arranged in a diamond.
struct FaceButtonsView: View {
    let scale: CGFloat

    private let radius: CGFloat = 30

    var body: some View {
        ZStack {
            FaceButton(label: "A", button: Int32(AZ_BUTTON_A), offset: CGSize(width: radius * scale, height: 0))
            FaceButton(label: "B", button: Int32(AZ_BUTTON_B), offset: CGSize(width: 0, height: radius * scale))
            FaceButton(label: "X", button: Int32(AZ_BUTTON_X), offset: CGSize(width: 0, height: -radius * scale))
            FaceButton(label: "Y", button: Int32(AZ_BUTTON_Y), offset: CGSize(width: -radius * scale, height: 0))
        }
    }
}

struct FaceButton: View {
    let label: String
    let button: Int32
    let offset: CGSize
    @State private var isPressed = false

    var body: some View {
        Button {
            az_button_event(button, true)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isPressed ? .black : .white)
                .frame(width: 32, height: 32)
                .background(isPressed ? .white : .white.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .offset(offset)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
            az_button_event(button, pressing)
        }, perform: {})
    }
}

/// L/R trigger button.
struct TriggerButton: View {
    let label: String
    let button: Int32
    let scale: CGFloat
    @State private var isPressed = false

    var body: some View {
        Button {
            az_button_event(button, true)
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50 * scale, height: 28 * scale)
                .background(isPressed ? .white.opacity(0.6) : .white.opacity(0.3),
                           in: Capsule())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
            az_button_event(button, pressing)
        }, perform: {})
    }
}

/// Small center button (Start, Select).
struct SmallButton: View {
    let label: String
    let button: Int32
    let scale: CGFloat
    @State private var isPressed = false

    var body: some View {
        Button {
            az_button_event(button, true)
        } label: {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36 * scale, height: 16 * scale)
                .background(.white.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
            az_button_event(button, pressing)
        }, perform: {})
    }
}

/// Virtual analog stick (circle-pad style).
struct AnalogStickView: View {
    @Binding var position: CGPoint
    let label: String
    let frameSize: CGSize
    let center: CGPoint
    let onPositionChanged: (CGFloat, CGFloat) -> Void

    @State private var isDragging = false
    @State private var stickCenter: CGPoint = .zero

    private var knobRadius: CGFloat { frameSize.width / 2 }
    private var maxRadius: CGFloat { knobRadius * 2 }

    var body: some View {
        Circle()
            .fill(.white.opacity(0.15))
            .frame(width: frameSize.width * 2, height: frameSize.height * 2)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: frameSize.width, height: frameSize.height)
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
