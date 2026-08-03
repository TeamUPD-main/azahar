// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Loading screen displayed while a game is being loaded.
/// Shows the game icon extracted from the ROM file.
struct EmulationLoadingView: View {
    let gameTitle: String
    let gamePath: String
    
    @State private var iconImage: UIImage?
    @State private var loadingProgress: Double = 0
    @State private var loadingMessage: String = "Loading game..."
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Game icon display
                if let icon = iconImage {
                    Image(uiImage: icon)
                        .resizable()
                        .interpolation(.none) // Preserve pixel art appearance
                        .frame(width: 192, height: 192)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                } else {
                    // Placeholder while icon loads
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 192, height: 192)
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.5)
                        )
                }
                
                // Game title
                Text(gameTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Loading indicator
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    Text(loadingMessage)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .onAppear {
            loadGameIcon()
        }
    }
    
    /// Extracts and loads the game icon from the ROM file
    private func loadGameIcon() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Buffer for 48x48 RGB565 icon
            let iconSize = 48 * 48
            var iconData = [UInt16](repeating: 0, count: iconSize)
            
            let pixelCount = az_get_game_icon(gamePath, &iconData, Int32(iconSize))
            
            guard pixelCount == iconSize else {
                // Icon extraction failed, keep placeholder
                return
            }
            
            // Convert RGB565 to RGBA8888 for UIImage
            let image = createImageFromRGB565(iconData, width: 48, height: 48)
            
            DispatchQueue.main.async {
                self.iconImage = image
            }
        }
    }
    
    /// Converts RGB565 pixel data to a UIImage
    private func createImageFromRGB565(_ pixels: [UInt16], width: Int, height: Int) -> UIImage? {
        // Create RGBA8888 buffer
        var rgbaPixels = [UInt8](repeating: 0, count: width * height * 4)
        
        for i in 0..<pixels.count {
            let rgb565 = pixels[i]
            
            // Extract RGB components from RGB565
            let r5 = UInt8((rgb565 >> 11) & 0x1F)
            let g6 = UInt8((rgb565 >> 5) & 0x3F)
            let b5 = UInt8(rgb565 & 0x1F)
            
            // Convert to 8-bit (scale up)
            let r8 = (r5 << 3) | (r5 >> 2)
            let g8 = (g6 << 2) | (g6 >> 4)
            let b8 = (b5 << 3) | (b5 >> 2)
            
            // Write RGBA pixel
            let offset = i * 4
            rgbaPixels[offset + 0] = r8
            rgbaPixels[offset + 1] = g8
            rgbaPixels[offset + 2] = b8
            rgbaPixels[offset + 3] = 255 // Alpha
        }
        
        // Create CGImage from pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let dataProvider = CGDataProvider(data: Data(rgbaPixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    EmulationLoadingView(
        gameTitle: "The Legend of Zelda: Ocarina of Time 3D",
        gamePath: "/path/to/game.3ds"
    )
}
