// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_PASSWORDS_H_
#define ROOM_CORE_ROOM_PASSWORDS_H_

#import <Foundation/Foundation.h>

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"

class Profile;

namespace password_manager {
class PasswordImporter;
class SavedPasswordsPresenter;
struct ImportResults;
}  // namespace password_manager

namespace room {

// A profile's password import (4.3b): Chrome's PasswordImporter over a
// SavedPasswordsPresenter of the profile's password stores, as Chrome's
// StartupPasswordsImporter wires it. One import at a time; the presenter
// loads the saved passwords once (its Init) so conflicts are found against
// them. The CSV is validated and parsed off the UI thread by the importer
// (a thread-pool task, then the sandboxed CSV parser service).
class PasswordImport {
 public:
  // The result dictionary documented at -[RoomProfile
  // importPasswordsFromCSV:replaceConflicts:completion:].
  using Completion = void (^)(NSDictionary<NSString*, id>*);

  explicit PasswordImport(Profile* profile);
  PasswordImport(const PasswordImport&) = delete;
  PasswordImport& operator=(const PasswordImport&) = delete;
  ~PasswordImport();

  // Imports `csv` into the profile store. Conflicts (a saved password for the
  // same site and username that differs) are all replaced or all kept.
  // `completion` runs once on the UI thread.
  void Start(std::string csv, bool replace_conflicts, Completion completion);

 private:
  void OnPresenterReady(std::string csv);
  void OnFirstPass(const password_manager::ImportResults& results);
  void Finish(const password_manager::ImportResults& results);
  void Fail(NSString* status);

  raw_ptr<Profile> profile_;
  std::unique_ptr<password_manager::SavedPasswordsPresenter> presenter_;
  std::unique_ptr<password_manager::PasswordImporter> importer_;
  bool presenter_ready_ = false;
  bool active_ = false;
  bool replace_conflicts_ = false;
  // The first pass's conflicting rows (site, username), with their outcome.
  NSMutableArray<NSDictionary<NSString*, id>*>* conflicts_;
  Completion completion_;
  base::WeakPtrFactory<PasswordImport> weak_factory_{this};
};

}  // namespace room

#endif  // ROOM_CORE_ROOM_PASSWORDS_H_
