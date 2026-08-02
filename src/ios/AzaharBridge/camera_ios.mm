// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#import <AVFoundation/AVFoundation.h>

#include <atomic>
#include <mutex>
#include <thread>

#include "common/assert.h"
#include "common/logging/log.h"
#include "common/thread.h"
#include "core/frontend/camera/blank_camera.h"
#include "ios/AzaharBridge/camera_ios.h"

namespace Camera::IOS {

/// Shared state between the AVCaptureVideoDataOutput delegate (capture queue)
/// and the emulation thread reading frames.
struct FrameBuffer {
    std::mutex mutex;
    std::vector<u16> data;
    u32 width = 0;
    u32 height = 0;
    bool mirror = false;
    bool invert = false;
    bool has_frame = false;
};

/// Converts a BGRA32 pixel buffer into an RGB565 frame at the requested size,
/// honoring mirror/invert. Runs on the capture queue.
void ConvertBGRAtoRGB565(CVPixelBufferRef pixel_buffer, FrameBuffer& buffer) {
    CVPixelBufferLockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
    const u8* src_base = static_cast<const u8*>(CVPixelBufferGetBaseAddress(pixel_buffer));
    const size_t src_row_bytes = CVPixelBufferGetBytesPerRow(pixel_buffer);
    const size_t src_width = CVPixelBufferGetWidth(pixel_buffer);
    const size_t src_height = CVPixelBufferGetHeight(pixel_buffer);
    if (!src_base) {
        CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
        return;
    }

    u32 out_width, out_height;
    bool mirror, invert;
    {
        std::lock_guard<std::mutex> lock(buffer.mutex);
        out_width = buffer.width;
        out_height = buffer.height;
        mirror = buffer.mirror;
        invert = buffer.invert;
    }
    if (out_width == 0 || out_height == 0) {
        out_width = static_cast<u32>(src_width);
        out_height = static_cast<u32>(src_height);
    }

    std::vector<u16> converted(static_cast<std::size_t>(out_width) * out_height);
    for (u32 y = 0; y < out_height; ++y) {
        size_t sy = (y * src_height) / out_height;
        if (invert) {
            sy = src_height - 1 - sy;
        }
        const u8* row = src_base + sy * src_row_bytes;
        for (u32 x = 0; x < out_width; ++x) {
            size_t sx = (x * src_width) / out_width;
            if (mirror) {
                sx = src_width - 1 - sx;
            }
            const u8* p = row + sx * 4;
            const u16 rgb565 = static_cast<u16>(((p[2] >> 3) << 11) | ((p[1] >> 2) << 5) | (p[0] >> 3));
            converted[static_cast<std::size_t>(y) * out_width + x] = rgb565;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);

    std::lock_guard<std::mutex> lock(buffer.mutex);
    buffer.data.swap(converted);
    buffer.width = out_width;
    buffer.height = out_height;
    buffer.has_frame = true;
}

} // namespace Camera::IOS

// MARK: - Sample buffer delegate (must be at global scope for ObjC)

/// Receives camera frames on the capture queue and writes RGB565 data into the
/// shared FrameBuffer.
@interface AZCameraDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic) std::shared_ptr<Camera::IOS::FrameBuffer> frameBuffer;
@end

@implementation AZCameraDelegate
- (void)captureOutput:(AVCaptureOutput*)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection*)connection {
    CVPixelBufferRef pixel_buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixel_buffer || !self.frameBuffer) {
        return;
    }
    Camera::IOS::ConvertBGRAtoRGB565(pixel_buffer, *self.frameBuffer);
}
@end

namespace Camera::IOS {

// MARK: - Interface

Interface::Interface(const std::string& config_, const Service::CAM::Flip& flip)
    : config(config_), is_front(config == FrontCameraPlaceholder) {
    mirror = base_mirror =
        flip == Service::CAM::Flip::Horizontal || flip == Service::CAM::Flip::Reverse;
    invert = base_invert =
        flip == Service::CAM::Flip::Vertical || flip == Service::CAM::Flip::Reverse;
    buffer = std::make_shared<FrameBuffer>();
}

Interface::~Interface() {
    StopCapture();
    session_ptr = nullptr;
    delegate_ptr = nullptr;
}

bool IsCameraAuthorized() {
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
    case AVAuthorizationStatusAuthorized:
        return true;
    case AVAuthorizationStatusNotDetermined: {
        // Prompt synchronously; runs rarely (first camera use).
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block bool granted = false;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL ok) {
                                   granted = ok;
                                   dispatch_semaphore_signal(sem);
                                 }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        return granted;
    }
    default:
        return false;
    }
}

void Interface::StartCapture() {
    if (session_ptr) {
        // Already capturing
        return;
    }
    if (!IsCameraAuthorized()) {
        LOG_WARNING(Service_CAM, "Camera access denied; using black frames");
        return;
    }

    // Resolve the capture device
    AVCaptureDevice* device = nullptr;
    if (is_front) {
        device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                    mediaType:AVMediaTypeVideo
                                                     position:AVCaptureDevicePositionFront];
    } else if (config == BackCameraPlaceholder) {
        device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                    mediaType:AVMediaTypeVideo
                                                     position:AVCaptureDevicePositionBack];
    } else {
        device = [AVCaptureDevice deviceWithUniqueID:[NSString stringWithUTF8String:config.c_str()]];
    }
    if (!device) {
        LOG_ERROR(Service_CAM, "No camera device available for '{}'", config);
        return;
    }

    NSError* error = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        LOG_ERROR(Service_CAM, "Failed to create camera input: {}", error.localizedDescription.UTF8String);
        return;
    }

    AVCaptureSession* session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPreset640x480;
    if (![session canAddInput:input]) {
        LOG_ERROR(Service_CAM, "Camera input rejected by session");
        return;
    }
    [session addInput:input];

    AZCameraDelegate* delegate = [[AZCameraDelegate alloc] init];
    delegate.frameBuffer = buffer;

    dispatch_queue_t queue =
        dispatch_queue_create("org.azahar.camera", DISPATCH_QUEUE_SERIAL);
    AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
    output.videoSettings = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    };
    output.alwaysDiscardsLateVideoFrames = YES;
    [output setSampleBufferDelegate:delegate queue:queue];
    if (![session canAddOutput:output]) {
        LOG_ERROR(Service_CAM, "Camera output rejected by session");
        return;
    }
    [session addOutput:output];

    dispatch_async(queue, ^{
      [session startRunning];
    });

    // Transfer ownership to the C++ object so the session and delegate survive
    // past this function (ARC would otherwise release the locals).
    session_ptr = (__bridge_retained void*)session;
    delegate_ptr = (__bridge_retained void*)delegate;
    LOG_INFO(Service_CAM, "Camera '{}' capturing started", config);
}

void Interface::StopCapture() {
    if (!session_ptr) {
        return;
    }
    AVCaptureSession* session = (__bridge_transfer AVCaptureSession*)session_ptr;
    AZCameraDelegate* delegate = (__bridge_transfer AZCameraDelegate*)delegate_ptr;
    session_ptr = nullptr;
    delegate_ptr = nullptr;

    dispatch_queue_t queue =
        dispatch_queue_create("org.azahar.camera.stop", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
      [session stopRunning];
      for (AVCaptureInput* input in session.inputs) {
          [session removeInput:input];
      }
      for (AVCaptureOutput* output in session.outputs) {
          [session removeOutput:output];
      }
    });

    // Release the delegate on its capture queue after the session stops.
    dispatch_async(queue, ^{
      (void)delegate;
    });
    LOG_INFO(Service_CAM, "Camera capturing stopped");
}

void Interface::SetResolution(const Service::CAM::Resolution& resolution_) {
    std::lock_guard<std::mutex> lock(buffer->mutex);
    resolution = resolution_;
    buffer->width = resolution.width;
    buffer->height = resolution.height;
}

void Interface::SetFlip(Service::CAM::Flip flip) {
    std::lock_guard<std::mutex> lock(buffer->mutex);
    mirror = flip == Service::CAM::Flip::Horizontal || flip == Service::CAM::Flip::Reverse;
    invert = flip == Service::CAM::Flip::Vertical || flip == Service::CAM::Flip::Reverse;
    buffer->mirror = mirror;
    buffer->invert = invert;
}

void Interface::SetFormat(Service::CAM::OutputFormat format_) {
    format = format_;
}

std::vector<u16> Interface::ReceiveFrame() {
    u32 width = resolution.width;
    u32 height = resolution.height;
    if (width == 0 || height == 0) {
        // No resolution configured yet; produce a single black pixel.
        return {0};
    }

    std::lock_guard<std::mutex> lock(buffer->mutex);
    if (!buffer->has_frame) {
        return std::vector<u16>(static_cast<std::size_t>(width) * height);
    }
    return buffer->data;
}

bool Interface::IsPreviewAvailable() {
    return IsCameraAuthorized();
}

// MARK: - Factory

std::unique_ptr<CameraInterface> Factory::Create(const std::string& config,
                                                 const Service::CAM::Flip& flip) {
    return std::make_unique<Interface>(config, flip);
}

} // namespace Camera::IOS
