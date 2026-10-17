// Copyright 2026 Jonas Lekevicius. All rights reserved.
#ifndef ROOM_CORE_CONTENT_BLOCKING_NETWORK_BLOCKING_H_
#define ROOM_CORE_CONTENT_BLOCKING_NETWORK_BLOCKING_H_

#include "base/functional/callback.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

namespace room {

// Sets patch 0026's hook: every URLLoaderFactory a profile creates while
// blocking is on gets the content-blocking proxy (browser process, once).
void InstallNetworkBlockingHook();

// Requests blocked on the page's current document (the main frame and its
// subframes; reset when the primary page changes).
class BlockedRequestCounter
    : public content::WebContentsObserver,
      public content::WebContentsUserData<BlockedRequestCounter> {
 public:
  using ChangedCallback =
      base::RepeatingCallback<void(content::WebContents*, int)>;
  // RoomCore's page wrapper listens (one listener for the process).
  static void SetChangedCallback(ChangedCallback callback);
  static int CountFor(content::WebContents* contents);

  ~BlockedRequestCounter() override;
  void Increment();
  int count() const { return count_; }

 private:
  friend class content::WebContentsUserData<BlockedRequestCounter>;
  explicit BlockedRequestCounter(content::WebContents* contents);

  // content::WebContentsObserver:
  void PrimaryPageChanged(content::Page& page) override;

  void Notify();

  int count_ = 0;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace room

#endif  // ROOM_CORE_CONTENT_BLOCKING_NETWORK_BLOCKING_H_
