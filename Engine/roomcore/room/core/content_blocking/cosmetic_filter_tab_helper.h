// Copyright 2026 Jonas Lekevicius. All rights reserved.
#ifndef ROOM_CORE_CONTENT_BLOCKING_COSMETIC_FILTER_TAB_HELPER_H_
#define ROOM_CORE_CONTENT_BLOCKING_COSMETIC_FILTER_TAB_HELPER_H_

#include <string>

#include "base/functional/callback.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

namespace room {

// Browser side of the renderer agent, one per Room page: at each
// cross-document commit in any of the page's frames it pushes that
// document's cosmetic resources (hide selectors, scriptlets, the
// cookie-banner script) over the frame's associated interfaces, with a host
// remote for the document's later questions (generic selectors) and its
// cookie-banner result.
class CosmeticFilterTabHelper
    : public content::WebContentsObserver,
      public content::WebContentsUserData<CosmeticFilterTabHelper> {
 public:
  // (page, consent platform, opted out): RoomCore's page wrapper listens.
  using CookieBannerCallback =
      base::RepeatingCallback<void(content::WebContents*,
                                   const std::string&,
                                   bool)>;
  static void SetCookieBannerCallback(CookieBannerCallback callback);

  ~CosmeticFilterTabHelper() override;

 private:
  friend class content::WebContentsUserData<CosmeticFilterTabHelper>;
  explicit CosmeticFilterTabHelper(content::WebContents* contents);

  // content::WebContentsObserver:
  void ReadyToCommitNavigation(
      content::NavigationHandle* navigation_handle) override;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace room

#endif  // ROOM_CORE_CONTENT_BLOCKING_COSMETIC_FILTER_TAB_HELPER_H_
