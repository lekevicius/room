#import "CEFBridge.h"

#include "include/cef_application_mac.h"

@interface RoomCEFApplication () <CefAppProtocol>
@end

@implementation RoomCEFApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

- (void)terminate:(id)sender {
  if (self.terminationHandler) {
    self.terminationHandler();
  } else {
    [RoomCEFRuntime quitMessageLoop];
  }
  // Return without exiting: the process exits after CefShutdown().
}

@end
