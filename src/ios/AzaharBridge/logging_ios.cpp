// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "common/logging/backend.h"
#include "common/logging/filter.h"
#include "ios/AzaharBridge/logging_ios.h"

namespace AzaharLogging {

namespace {
class IOSBackend final : public Common::Log::Backend {
public:
    void LogMessage(Common::Log::Level level, Common::Log::Class log_class,
                    const char* filename, unsigned int pid, unsigned int tid,
                    const char* function, int linenumber,
                    const char* log_text) override {
        // Forward to the default file backend; OSLog integration can be added
        // separately via os_log() if desired.
    }
};
} // Anonymous namespace

void Init() {
    Common::Log::Initialize();
    Common::Log::Start();
}

} // namespace AzaharLogging
