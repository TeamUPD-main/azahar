// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "common/logging/backend.h"
#include "common/logging/filter.h"
#include "ios/AzaharBridge/logging_ios.h"

namespace AzaharLogging {

void Init() {
    Common::Log::Initialize();
    
#ifdef _DEBUG
    // In debug builds, enable verbose logging for renderer, frontend, and core
    Common::Log::Filter filter;
    filter.ParseFilterString("*:Debug Render*:Trace Frontend:Trace Core:Debug");
    Common::Log::SetGlobalFilter(filter);
#endif
    
    Common::Log::Start();
}

} // namespace AzaharLogging
