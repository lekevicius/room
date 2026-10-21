// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "room/branding/room_branded_strings.h"

#include <array>
#include <string>
#include <string_view>

#include "base/logging.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/timer/elapsed_timer.h"
#include "chrome/common/chrome_version.h"
#include "chrome/grit/branded_strings.h"
#include "ui/base/resource/resource_bundle.h"

namespace room {
namespace {

// Every IDS_ id of Chrome's string headers (//room/branding:string_ids).
constexpr int kStringIds[] = {
#include "room/branding/room_string_ids.inc"
};

constexpr std::u16string_view kChromium = u"Chromium";

// Phrases that keep Chromium's name: the attribution (the about page links the name:
// "the <a …>Chromium</a> open source project") and another product's name.
constexpr std::array<std::u16string_view, 5> kKept = {
    u"Chromium open source project", u"Chromium</a> open source project", u"The Chromium Authors", u"Chromium OS",
    u"ChromiumOS"};

bool IsKept(const std::u16string& text, size_t at) {
  for (std::u16string_view phrase : kKept) {
    // The phrase may start before "Chromium" ("The Chromium Authors").
    const size_t lead = phrase.find(kChromium);
    if (at >= lead && text.compare(at - lead, phrase.size(), phrase) == 0) {
      return true;
    }
  }
  return false;
}

}  // namespace

std::u16string RebrandString(const std::u16string& text) {
  const std::u16string product = std::u16string(u"" PRODUCT_FULLNAME_STRING);
  std::u16string result;
  size_t from = 0;
  for (size_t at = text.find(kChromium); at != std::u16string::npos; at = text.find(kChromium, at + kChromium.size())) {
    result.append(text, from, at - from);
    result.append(IsKept(text, at) ? std::u16string(kChromium) : product);
    from = at + kChromium.size();
  }
  result.append(text, from, std::u16string::npos);
  return result;
}

void InstallBrandedStrings() {
  base::ElapsedTimer timer;
  ui::ResourceBundle& bundle = ui::ResourceBundle::GetSharedInstance();
  int overridden = 0;
  for (int id : kStringIds) {
    // The raw (UTF-8) string: no lookup failure CHECKs, and most strings never decode.
    const std::string raw = bundle.LoadLocalizedResourceString(id);
    if (raw.find("Chromium") == std::string::npos) {
      continue;
    }
    const std::u16string text = base::UTF8ToUTF16(raw);
    const std::u16string branded = RebrandString(text);
    if (branded != text) {
      bundle.OverrideLocaleStringResource(id, branded);
      ++overridden;
    }
  }
  // The about pages' company and copyright: BRANDING's (Room's), not Chromium's authors.
  const std::u16string company = std::u16string(u"" COMPANY_FULLNAME_STRING);
  bundle.OverrideLocaleStringResource(IDS_ABOUT_VERSION_COMPANY_NAME, company);
  std::u16string copyright = base::UTF8ToUTF16(bundle.LoadLocalizedResourceString(IDS_ABOUT_VERSION_COPYRIGHT));
  base::ReplaceSubstringsAfterOffset(&copyright, 0, u"The Chromium Authors", company);
  bundle.OverrideLocaleStringResource(IDS_ABOUT_VERSION_COPYRIGHT, copyright);
  LOG(INFO) << "RoomCore: branded strings: " << overridden << " of " << std::size(kStringIds)
            << " overridden in " << timer.Elapsed().InMicroseconds() << " us";
}

}  // namespace room
