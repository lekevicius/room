// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Context menus of Room pages (patch 0018): Chrome builds the menu
// (RenderViewContextMenuMac: every IDC_CONTENT_CONTEXT_* command, spelling
// suggestions, Add to dictionary, Look Up); the host shows its own NSMenu
// with Room's items first and answers with one of Chrome's commands or none.

#import "room/core/room_page_ui_internal.h"

#include <memory>
#include <optional>
#include <utility>

#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "components/renderer_context_menu/render_view_context_menu_base.h"
#include "content/public/browser/context_menu_params.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/blink/public/mojom/context_menu/context_menu.mojom.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/accelerators/platform_accelerator_cocoa.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/menus/simple_menu_model.h"

namespace room {
// Defined in chrome/browser/ui/views/tab_contents/
// chrome_web_contents_view_delegate_views_mac.mm
// (patches/0018-context-menu-hook.patch).
extern bool (*g_show_context_menu_hook)(
    content::WebContents*,
    std::unique_ptr<RenderViewContextMenuBase>&);
}  // namespace room

@interface RoomMenuItem ()
- (instancetype)initWithCommandId:(NSInteger)commandId
                             type:(RoomMenuItemType)type
                            title:(NSString*)title
                          enabled:(BOOL)enabled
                          checked:(BOOL)checked
                          groupId:(NSInteger)groupId
                    keyEquivalent:(NSString*)keyEquivalent
                     modifierMask:(NSEventModifierFlags)modifierMask
                          submenu:(NSArray<RoomMenuItem*>*)submenu;
@end

@implementation RoomMenuItem

@synthesize commandId = _commandId;
@synthesize type = _type;
@synthesize title = _title;
@synthesize enabled = _enabled;
@synthesize checked = _checked;
@synthesize groupId = _groupId;
@synthesize keyEquivalent = _keyEquivalent;
@synthesize keyEquivalentModifierMask = _keyEquivalentModifierMask;
@synthesize submenu = _submenu;

- (instancetype)initWithCommandId:(NSInteger)commandId
                             type:(RoomMenuItemType)type
                            title:(NSString*)title
                          enabled:(BOOL)enabled
                          checked:(BOOL)checked
                          groupId:(NSInteger)groupId
                    keyEquivalent:(NSString*)keyEquivalent
                     modifierMask:(NSEventModifierFlags)modifierMask
                          submenu:(NSArray<RoomMenuItem*>*)submenu {
  if ((self = [super init])) {
    _commandId = commandId;
    _type = type;
    _title = [title copy];
    _enabled = enabled;
    _checked = checked;
    _groupId = groupId;
    _keyEquivalent = [keyEquivalent copy];
    _keyEquivalentModifierMask = modifierMask;
    _submenu = [submenu copy];
  }
  return self;
}

- (NSString*)description {
  return _type == RoomMenuItemTypeSeparator
             ? @"—"
             : [NSString stringWithFormat:@"%@(%ld)%@", _title, (long)_commandId,
                                          _enabled ? @"" : @" disabled"];
}

@end

namespace {

// Keeps the menu Chrome built (and with it the RenderViewContextMenu's
// commands) until the host answers; dies with the page.
class ContextMenuHolder
    : public content::WebContentsUserData<ContextMenuHolder> {
 public:
  ~ContextMenuHolder() override = default;

  // Takes `menu`; a menu still open for this page is closed first.
  uint64_t Take(std::unique_ptr<RenderViewContextMenuBase> menu) {
    Close();
    menu_ = std::move(menu);
    menu_->OnMenuWillShow(Model());
    return ++generation_;
  }

  // The menu back, unanswered (the host does not show menus after all).
  std::unique_ptr<RenderViewContextMenuBase> Release(uint64_t generation) {
    if (generation != generation_ || !menu_) {
      return nullptr;
    }
    GetWebContents().SetShowingContextMenu(false);
    return std::move(menu_);
  }

  // The host's answer: Chrome's command, then the menu closes.
  void Finish(uint64_t generation, std::optional<int> command) {
    if (generation != generation_ || !menu_) {
      return;
    }
    base::WeakPtr<ContextMenuHolder> weak = weak_factory_.GetWeakPtr();
    if (command) {
      // Chrome's own enabled state (RenderViewContextMenu or an observer:
      // spelling, extensions).
      ui::SimpleMenuModel::Delegate* commands = menu_.get();
      if (commands->IsCommandIdEnabled(*command)) {
        menu_->ExecuteCommand(*command, /*event_flags=*/0);
      } else {
        LOG(WARNING) << "RoomCore: context menu command " << *command
                     << " is not enabled; ignored";
      }
      if (!weak || generation != generation_ || !menu_) {
        return;
      }
    }
    Close();
  }

  base::WeakPtr<ContextMenuHolder> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

 private:
  friend class content::WebContentsUserData<ContextMenuHolder>;
  explicit ContextMenuHolder(content::WebContents* contents)
      : content::WebContentsUserData<ContextMenuHolder>(*contents) {}

  ui::SimpleMenuModel* Model() {
    return const_cast<ui::SimpleMenuModel*>(&menu_->menu_model());
  }

  void Close() {
    if (!menu_) {
      return;
    }
    std::unique_ptr<RenderViewContextMenuBase> menu = std::move(menu_);
    menu->MenuClosed(const_cast<ui::SimpleMenuModel*>(&menu->menu_model()));
  }

  std::unique_ptr<RenderViewContextMenuBase> menu_;
  uint64_t generation_ = 0;
  base::WeakPtrFactory<ContextMenuHolder> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(ContextMenuHolder);

// Items Room cannot offer: Chrome's other profiles and "Use Enhanced Spell
// Check" (Google's spelling service behind Chrome's consent; hidden, B-74).
// "Open Link in Incognito Window" shows since 4.8b (B-50): the navigator hook
// hands it to the host's incognito window.
bool IsOmitted(int command_id) {
  return command_id == IDC_CONTENT_CONTEXT_SPELLING_TOGGLE ||
         command_id == IDC_CONTENT_CONTEXT_OPENLINKINPROFILE ||
         (command_id >= IDC_OPEN_LINK_IN_PROFILE_FIRST &&
          command_id < IDC_CONTENT_CONTEXT_START_SMART_SELECTION_ACTION1);
}

NSArray<RoomMenuItem*>* ItemsOf(const ui::MenuModel& model) {
  NSMutableArray<RoomMenuItem*>* items = [NSMutableArray array];
  for (size_t i = 0; i < model.GetItemCount(); ++i) {
    if (!model.IsVisibleAt(i)) {
      continue;
    }
    const int command = model.GetCommandIdAt(i);
    RoomMenuItemType type = RoomMenuItemTypeCommand;
    NSArray<RoomMenuItem*>* submenu = nil;
    switch (model.GetTypeAt(i)) {
      case ui::MenuModel::TYPE_SEPARATOR:
        type = RoomMenuItemTypeSeparator;
        break;
      case ui::MenuModel::TYPE_CHECK:
        type = RoomMenuItemTypeCheck;
        break;
      case ui::MenuModel::TYPE_RADIO:
        type = RoomMenuItemTypeRadio;
        break;
      case ui::MenuModel::TYPE_SUBMENU:
        type = RoomMenuItemTypeSubmenu;
        if (ui::MenuModel* child = model.GetSubmenuModelAt(i)) {
          submenu = ItemsOf(*child);
        }
        break;
      default:
        break;
    }
    if (type != RoomMenuItemTypeSeparator && IsOmitted(command)) {
      continue;
    }
    NSString* key = @"";
    NSEventModifierFlags mask = 0;
    ui::Accelerator accelerator;
    if (type != RoomMenuItemTypeSeparator &&
        model.GetAcceleratorAt(i, &accelerator)) {
      KeyEquivalentAndModifierMask* equivalent =
          ui::GetKeyEquivalentAndModifierMaskFromAccelerator(accelerator);
      key = equivalent.keyEquivalent ?: @"";
      mask = equivalent.modifierMask;
    }
    const bool separator = type == RoomMenuItemTypeSeparator;
    [items addObject:[[RoomMenuItem alloc]
                         initWithCommandId:separator ? -1 : command
                                      type:type
                                     title:separator ? @""
                                                     : l10n_util::FixUpWindowsStyleLabel(
                                                           model.GetLabelAt(i))
                                   enabled:!separator && model.IsEnabledAt(i)
                                   checked:!separator && model.IsItemCheckedAt(i)
                                   groupId:type == RoomMenuItemTypeRadio
                                               ? model.GetGroupIdAt(i)
                                               : 0
                             keyEquivalent:key
                              modifierMask:mask
                                   submenu:submenu]];
  }
  return items;
}

RoomContextMenuMediaType ToRoomMediaType(
    blink::mojom::ContextMenuDataMediaType type) {
  using Type = blink::mojom::ContextMenuDataMediaType;
  switch (type) {
    case Type::kImage:
      return RoomContextMenuMediaTypeImage;
    case Type::kVideo:
      return RoomContextMenuMediaTypeVideo;
    case Type::kAudio:
      return RoomContextMenuMediaTypeAudio;
    case Type::kCanvas:
      return RoomContextMenuMediaTypeCanvas;
    case Type::kFile:
      return RoomContextMenuMediaTypeFile;
    case Type::kPlugin:
      return RoomContextMenuMediaTypePlugin;
    default:
      return RoomContextMenuMediaTypeNone;
  }
}

NSURL* ToNSURL(const GURL& url) {
  return url.is_valid() ? net::NSURLWithGURL(url) : nil;
}

NSString* ToNSString(const std::u16string& text) {
  return text.empty() ? nil : base::SysUTF16ToNSString(text);
}

}  // namespace

@interface RoomContextMenu ()
- (instancetype)initWithMenu:(const RenderViewContextMenuBase&)menu;
- (void)room_attachHolder:(base::WeakPtr<ContextMenuHolder>)holder
               generation:(uint64_t)generation;
@end

@implementation RoomContextMenu {
  base::WeakPtr<ContextMenuHolder> _holder;
  uint64_t _generation;
  BOOL _answered;
}

@synthesize items = _items;
@synthesize location = _location;
@synthesize pageURL = _pageURL;
@synthesize frameURL = _frameURL;
@synthesize linkURL = _linkURL;
@synthesize linkText = _linkText;
@synthesize sourceURL = _sourceURL;
@synthesize mediaType = _mediaType;
@synthesize selectionText = _selectionText;
@synthesize editable = _editable;
@synthesize misspelledWord = _misspelledWord;
@synthesize dictionarySuggestions = _dictionarySuggestions;

- (instancetype)initWithMenu:(const RenderViewContextMenuBase&)menu {
  if ((self = [super init])) {
    const content::ContextMenuParams& params = menu.params();
    _items = ItemsOf(menu.menu_model());
    _location = NSMakePoint(params.x, params.y);
    _pageURL = ToNSURL(params.page_url);
    _frameURL = ToNSURL(params.frame_url);
    _linkURL = ToNSURL(params.link_url);
    _linkText = ToNSString(params.link_text);
    _sourceURL = ToNSURL(params.src_url);
    _mediaType = ToRoomMediaType(params.media_type);
    _selectionText = ToNSString(params.selection_text);
    _editable = params.is_editable;
    _misspelledWord = ToNSString(params.misspelled_word);
    NSMutableArray<NSString*>* suggestions = [NSMutableArray array];
    for (const std::u16string& suggestion : params.dictionary_suggestions) {
      [suggestions addObject:base::SysUTF16ToNSString(suggestion)];
    }
    _dictionarySuggestions = [suggestions copy];
  }
  return self;
}

- (void)room_attachHolder:(base::WeakPtr<ContextMenuHolder>)holder
               generation:(uint64_t)generation {
  _holder = holder;
  _generation = generation;
}

- (void)selectCommand:(NSInteger)commandId {
  if (_answered) {
    return;
  }
  _answered = YES;
  if (_holder) {
    _holder->Finish(_generation, static_cast<int>(commandId));
  }
}

- (void)cancel {
  if (_answered) {
    return;
  }
  _answered = YES;
  if (_holder) {
    _holder->Finish(_generation, std::nullopt);
  }
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomContextMenu link=%@ text=%@ "
                                    @"media=%ld editable=%d misspelled=%@ "
                                    @"items=%@>",
                                    _linkURL, _linkText, (long)_mediaType,
                                    _editable, _misspelledWord,
                                    [_items componentsJoinedByString:@" | "]];
}

@end

namespace room {

void InstallContextMenuHook() {
  g_show_context_menu_hook =
      +[](content::WebContents* contents,
          std::unique_ptr<RenderViewContextMenuBase>& menu) -> bool {
    RoomWebContents* wrapper =
        WrapperAnswering(contents, @selector(webContents:willShowContextMenu:));
    if (!wrapper || !menu) {
      return false;
    }
    RoomContextMenu* roomMenu = [[RoomContextMenu alloc] initWithMenu:*menu];
    // The holder owns the menu before the host sees it: a host that shows
    // its menu modally answers inside the call below.
    ContextMenuHolder::CreateForWebContents(contents);
    ContextMenuHolder* holder = ContextMenuHolder::FromWebContents(contents);
    const uint64_t generation = holder->Take(std::move(menu));
    [roomMenu room_attachHolder:holder->GetWeakPtr() generation:generation];
    LOG(INFO) << "RoomCore: context menu "
              << base::SysNSStringToUTF8(roomMenu.description);
    id<RoomWebContentsDelegate> delegate = wrapper.delegate;
    if ([delegate webContents:wrapper willShowContextMenu:roomMenu]) {
      return true;
    }
    // The host does not show it: Chrome's runner does, if the page is
    // still there and nothing answered.
    if (ContextMenuHolder* current =
            ContextMenuHolder::FromWebContents(contents)) {
      menu = current->Release(generation);
    }
    return !menu;
  };
}

}  // namespace room
