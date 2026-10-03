// Copyright 2026 Jonas Lekevicius. All rights reserved.
#ifndef ROOM_CORE_ROOM_NETWORK_POLICY_H_
#define ROOM_CORE_ROOM_NETWORK_POLICY_H_
#include "base/callback_list.h"
namespace room {
// Install before ChromeMain. Lifetime covers profile creation and teardown.
base::CallbackListSubscription InstallNetworkPolicy();
}
#endif  // ROOM_CORE_ROOM_NETWORK_POLICY_H_
