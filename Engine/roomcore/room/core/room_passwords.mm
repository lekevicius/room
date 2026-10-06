// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_passwords.h"

#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/affiliations/affiliation_service_factory.h"
#include "chrome/browser/password_manager/factories/account_password_store_factory.h"
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/password_manager/core/browser/import/import_results.h"
#include "components/password_manager/core/browser/import/password_importer.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/browser/ui/saved_passwords_presenter.h"

namespace room {

namespace {

using password_manager::ImportEntry;
using password_manager::ImportResults;

NSString* StatusName(ImportResults::Status status) {
  switch (status) {
    case ImportResults::SUCCESS:
      return @"success";
    case ImportResults::IO_ERROR:
      return @"unreadable";
    case ImportResults::BAD_FORMAT:
      return @"badFormat";
    case ImportResults::MAX_FILE_SIZE:
      return @"tooLarge";
    case ImportResults::IMPORT_ALREADY_ACTIVE:
      return @"busy";
    case ImportResults::NUM_PASSWORDS_EXCEEDED:
      return @"tooMany";
    default:
      return @"failed";
  }
}

NSString* ReasonName(ImportEntry::Status status) {
  switch (status) {
    case ImportEntry::MISSING_PASSWORD:
      return @"missingPassword";
    case ImportEntry::MISSING_URL:
      return @"missingURL";
    case ImportEntry::INVALID_URL:
      return @"invalidURL";
    case ImportEntry::LONG_URL:
      return @"longURL";
    case ImportEntry::LONG_PASSWORD:
      return @"longPassword";
    case ImportEntry::LONG_USERNAME:
      return @"longUsername";
    case ImportEntry::LONG_NOTE:
    case ImportEntry::LONG_CONCATENATED_NOTE:
      return @"longNote";
    case ImportEntry::CONFLICT_PROFILE:
    case ImportEntry::CONFLICT_ACCOUNT:
      return @"conflictKept";
    default:
      return @"malformed";
  }
}

// One row the host lists: never the password.
NSDictionary<NSString*, id>* Row(const ImportEntry& entry, NSString* reason) {
  return @{
    @"url" : base::SysUTF8ToNSString(entry.url),
    @"username" : base::SysUTF8ToNSString(entry.username),
    @"reason" : reason,
  };
}

}  // namespace

PasswordImport::PasswordImport(Profile* profile) : profile_(profile) {
  presenter_ = std::make_unique<password_manager::SavedPasswordsPresenter>(
      AffiliationServiceFactory::GetForProfile(profile),
      ProfilePasswordStoreFactory::GetForProfile(
          profile, ServiceAccessType::EXPLICIT_ACCESS),
      AccountPasswordStoreFactory::GetForProfile(
          profile, ServiceAccessType::EXPLICIT_ACCESS));
  importer_ =
      std::make_unique<password_manager::PasswordImporter>(*presenter_);
}

PasswordImport::~PasswordImport() {
  // The profile is going (the quit): the host hears once that it ended.
  if (completion_) {
    completion_(@{@"status" : @"unavailable"});
  }
}

void PasswordImport::Start(std::string csv,
                           bool replace_conflicts,
                           Completion completion) {
  if (active_) {
    completion(@{@"status" : @"busy"});
    return;
  }
  active_ = true;
  replace_conflicts_ = replace_conflicts;
  completion_ = [completion copy];
  conflicts_ = [NSMutableArray array];
  if (presenter_ready_) {
    OnPresenterReady(std::move(csv));
    return;
  }
  // Without a profile store the presenter never reports ready.
  if (!ProfilePasswordStoreFactory::GetForProfile(
          profile_, ServiceAccessType::EXPLICIT_ACCESS)) {
    Fail(@"unavailable");
    return;
  }
  presenter_->Init(base::BindOnce(&PasswordImport::OnPresenterReady,
                                  weak_factory_.GetWeakPtr(), std::move(csv)));
}

void PasswordImport::OnPresenterReady(std::string csv) {
  presenter_ready_ = true;
  importer_->Import(std::move(csv),
                    password_manager::PasswordForm::Store::kProfileStore,
                    base::BindOnce(&PasswordImport::OnFirstPass,
                                   weak_factory_.GetWeakPtr()));
}

void PasswordImport::OnFirstPass(const ImportResults& results) {
  if (results.status != ImportResults::CONFLICTS) {
    Finish(results);
    return;
  }
  // Asked once for all (the host's policy): every conflict replaced, or none.
  std::vector<int> selected;
  for (const ImportEntry& entry : results.displayed_entries) {
    [conflicts_ addObject:Row(entry, replace_conflicts_ ? @"conflictReplaced"
                                                        : @"conflictKept")];
    if (replace_conflicts_) {
      selected.push_back(entry.id);
    }
  }
  importer_->ContinueImport(selected,
                            base::BindOnce(&PasswordImport::Finish,
                                           weak_factory_.GetWeakPtr()));
}

void PasswordImport::Finish(const ImportResults& results) {
  NSMutableArray<NSDictionary<NSString*, id>*>* rows =
      [NSMutableArray arrayWithArray:conflicts_];
  for (const ImportEntry& entry : results.displayed_entries) {
    [rows addObject:Row(entry, ReasonName(entry.status))];
  }
  NSUInteger conflicts = conflicts_.count;
  NSDictionary<NSString*, id>* result = @{
    @"status" : StatusName(results.status),
    @"imported" : @(results.number_imported),
    @"conflicts" : @(conflicts),
    @"replaced" : @(replace_conflicts_ ? conflicts : 0),
    @"rows" : rows,
  };
  LOG(INFO) << "RoomCore: password import " << results.status << ": "
            << results.number_imported << " imported, " << conflicts
            << " conflicts" << (replace_conflicts_ ? " replaced" : " kept")
            << ", " << results.displayed_entries.size() << " rows skipped";
  Completion completion = completion_;
  completion_ = nil;
  conflicts_ = nil;
  active_ = false;
  if (completion) {
    completion(result);
  }
}

void PasswordImport::Fail(NSString* status) {
  Completion completion = completion_;
  completion_ = nil;
  conflicts_ = nil;
  active_ = false;
  if (completion) {
    completion(@{@"status" : status});
  }
}

}  // namespace room
