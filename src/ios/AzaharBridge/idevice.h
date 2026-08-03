// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// Forward declarations for opaque types
typedef void* idevice_adapter_t;
typedef void* idevice_handshake_t;
typedef void* idevice_debug_proxy_t;
typedef void* idevice_remote_server_t;

// Logger callback type
typedef void (*idevice_log_func)(const char* message);

// Debug callback type (for JavaScript execution on TXM devices)
typedef void (*idevice_debug_callback)(
    int32_t pid,
    idevice_debug_proxy_t debug_proxy,
    idevice_remote_server_t remote_server,
    void* semaphore
);

// Error codes
typedef enum {
    IDEVICE_SUCCESS = 0,
    IDEVICE_ERROR_GENERIC = -1,
    IDEVICE_ERROR_NOT_CONNECTED = -2,
    IDEVICE_ERROR_NO_PAIRING = -3,
    IDEVICE_ERROR_MOUNT_FAILED = -4,
    IDEVICE_ERROR_APP_NOT_FOUND = -5,
    IDEVICE_ERROR_PERMISSION_DENIED = -6,
} idevice_error_t;

// Connection management
idevice_error_t start_tunnel(const char* pairing_file_path, 
                              idevice_adapter_t* out_adapter,
                              idevice_handshake_t* out_handshake);
void stop_tunnel(idevice_adapter_t adapter);

// Developer Disk Image mounting
idevice_error_t mount_developer_image(idevice_adapter_t adapter,
                                       idevice_handshake_t handshake,
                                       const char* image_path,
                                       const char* signature_path,
                                       const char* trustcache_path,
                                       idevice_log_func logger);

bool is_developer_image_mounted(idevice_adapter_t adapter,
                                 idevice_handshake_t handshake);

// JIT enablement
idevice_error_t debug_app(idevice_adapter_t adapter,
                          idevice_handshake_t handshake,
                          const char* bundle_id,
                          idevice_log_func logger,
                          idevice_debug_callback callback);

idevice_error_t debug_app_pid(idevice_adapter_t adapter,
                               idevice_handshake_t handshake,
                               int32_t pid,
                               idevice_log_func logger,
                               idevice_debug_callback callback);

// App launching
idevice_error_t launch_app_via_proxy(idevice_adapter_t adapter,
                                      idevice_handshake_t handshake,
                                      const char* bundle_id,
                                      idevice_log_func logger);

// Device info
typedef struct {
    char device_name[256];
    char device_class[64];
    char product_type[64];
    char product_version[64];
    char build_version[64];
    char unique_device_id[256];
    uint64_t total_disk_capacity;
    uint64_t total_system_capacity;
} idevice_info_t;

idevice_error_t get_device_info(idevice_adapter_t adapter,
                                 idevice_handshake_t handshake,
                                 idevice_info_t* out_info);

// Process management
typedef struct {
    int32_t pid;
    char name[256];
    char bundle_id[256];
} idevice_process_t;

idevice_error_t get_process_list(idevice_adapter_t adapter,
                                  idevice_handshake_t handshake,
                                  idevice_process_t** out_processes,
                                  size_t* out_count);

void free_process_list(idevice_process_t* processes);

idevice_error_t kill_process(idevice_adapter_t adapter,
                              idevice_handshake_t handshake,
                              int32_t pid);

// Get current process PID
int32_t get_current_pid(void);

// Get bundle ID for current app
const char* get_current_bundle_id(void);

#ifdef __cplusplus
}
#endif
