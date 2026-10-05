// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_APP_CONTROLLER_H_
#define ROOM_CORE_ROOM_APP_CONTROLLER_H_

namespace room {

// Installs the AppController hook (patches/0013): AppController.sharedController
// answers with //room's RoomAppController, and Chrome builds no main menu and
// never takes NSApp.delegate (the host's). Called before ChromeMain.
void InstallAppController();

// Chrome's close path (what BrowserCrApplication -terminate: asks the
// controller for): BrowserCloseManager runs beforeunload handlers on every
// Browser's tabs, a "stay" cancels, otherwise every Browser closes and
// chrome::OnAppExiting() follows.
void TryToTerminateApplication();

}  // namespace room

#endif  // ROOM_CORE_ROOM_APP_CONTROLLER_H_
