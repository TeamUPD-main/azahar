// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "common/logging/backend.h"
#include "ios/AzaharBridge/logging_ios.h"

namespace AzaharLogging {

void Init() {
    Common::Log::Initialize();
    Common::Log::Start();
}

} // namespace AzaharLogging
