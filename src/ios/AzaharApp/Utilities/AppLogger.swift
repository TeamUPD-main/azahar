// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation
import SwiftUI

/// Comprehensive logging utility for Swift UI lifecycle and app events
/// Logs to both Xcode console and the C++ logging system
enum AppLogger {
    
    private static var isAllLoggingEnabled: Bool {
        let level = UserDefaults.standard.integer(forKey: "Debugging_log_filter_level")
        return level == -1 || level == 0
    }
    
    /// Log view lifecycle events (onAppear, onDisappear)
    static func viewLifecycle(_ viewName: String, event: String) {
        guard isAllLoggingEnabled else { return }
        let message = "[UI] \(viewName): \(event)"
        print(message)
        az_log_info(message)
    }
    
    /// Log navigation events
    static func navigation(from: String, to: String) {
        guard isAllLoggingEnabled else { return }
        let message = "[Navigation] \(from) -> \(to)"
        print(message)
        az_log_info(message)
    }
    
    /// Log user actions
    static func userAction(_ action: String, details: String = "") {
        guard isAllLoggingEnabled else { return }
        let message = details.isEmpty ? "[Action] \(action)" : "[Action] \(action): \(details)"
        print(message)
        az_log_info(message)
    }
    
    /// Log ROM/game operations
    static func gameOperation(_ operation: String, path: String = "", titleId: UInt64 = 0) {
        let titleStr = titleId != 0 ? String(format: " (TitleID: %016llX)", titleId) : ""
        let pathStr = !path.isEmpty ? " Path: \(path)" : ""
        let message = "[Game] \(operation)\(titleStr)\(pathStr)"
        print(message)
        az_log_info(message)
    }
    
    /// Log errors with full context
    static func error(_ context: String, error: Error) {
        let message = "[Error] \(context): \(error.localizedDescription)"
        print(message)
        az_log_error(message)
    }
    
    /// Log errors with custom message
    static func error(_ context: String, message: String) {
        let msg = "[Error] \(context): \(message)"
        print(msg)
        az_log_error(msg)
    }
    
    /// Log state changes
    static func stateChange(_ component: String, from: String, to: String) {
        guard isAllLoggingEnabled else { return }
        let message = "[State] \(component): \(from) -> \(to)"
        print(message)
        az_log_info(message)
    }
    
    /// Log generic info
    static func info(_ message: String) {
        print("[Info] \(message)")
        az_log_info(message)
    }
    
    /// Log debug info (only when All or Trace/Debug is enabled)
    static func debug(_ message: String) {
        guard isAllLoggingEnabled else { return }
        print("[Debug] \(message)")
        az_log_debug(message)
    }
}

// Helper bridge functions for logging from Swift
private func az_log_info(_ message: String) {
    message.withCString { ptr in
        az_log_message(0, ptr) // 0 = Info level
    }
}

private func az_log_debug(_ message: String) {
    message.withCString { ptr in
        az_log_message(1, ptr) // 1 = Debug level
    }
}

private func az_log_error(_ message: String) {
    message.withCString { ptr in
        az_log_message(4, ptr) // 4 = Error level
    }
}

// C bridge function declarations
@_silgen_name("az_log_message")
private func az_log_message(_ level: Int32, _ message: UnsafePointer<CChar>)
