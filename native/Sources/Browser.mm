// Portions copyright (c) 2013 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// macOS event-loop setup adapts cefsimple under ../ThirdParty/CEF-LICENSE.txt.
#import <AppKit/AppKit.h>
#include <map>
#include <vector>
#include <set>
#include <limits.h>
#include <stdlib.h>
#include "Bridge.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_parser.h"
#include "include/cef_download_item.h"
#include "include/cef_cookie.h"
#include "include/cef_task.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

namespace {
struct Page {
  CefRefPtr<CefBrowser> browser;
  __strong NSView* view = nil;
  std::string space, title, url;
  bool loading = false, back = false, forward = false, preserve = false, closing = false;
};
std::map<std::string, Page> pages;
std::map<std::string, CefRefPtr<CefRequestContext>> contexts;
__strong NSView* host;
std::string selected, splitFirst, splitSecond;
double splitRatio = 0.5;
std::map<std::string, CefRefPtr<CefDownloadItemCallback>> downloads;
std::set<std::string> readyDownloads, cancelDownloads;
class CancelDownloadTask final : public CefTask {
 public:
  explicit CancelDownloadTask(CefRefPtr<CefDownloadItemCallback> callback) : callback_(callback) {}
  void Execute() override { callback_->Cancel(); }
 private:
  CefRefPtr<CefDownloadItemCallback> callback_;
  IMPLEMENT_REFCOUNTING(CancelDownloadTask);
};
bool Visible(const std::string& id) { return id == selected || id == splitFirst || id == splitSecond; }
bool quitting = false, exiting = false;
class Completion final : public CefCompletionCallback {
 public:
  void OnComplete() override {}
 private:
  IMPLEMENT_REFCOUNTING(Completion);
};
class QuitTask final : public CefTask {
 public:
  void Execute() override { CefQuitMessageLoop(); }
 private:
  IMPLEMENT_REFCOUNTING(QuitTask);
};
CefRefPtr<CefBrowser> Active() {
  auto found = pages.find(selected);
  return found == pages.end() ? nullptr : found->second.browser;
}
bool IsWebsite(const CefString& value) {
  CefURLParts parts;
  if (!CefParseURL(value, parts)) return false;
  const std::string scheme = CefString(&parts.scheme);
  return scheme == "http" || scheme == "https";
}
CefRefPtr<CefRequestContext> Context(const std::string& profile) {
  if (profile.empty() || profile.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-") != std::string::npos) return nullptr;
  if (contexts.count(profile)) return contexts.at(profile);
  CefRequestContextSettings settings;
  NSString* root = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_USER_DATA"];
  if (!root) root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Derivative Native Prototype"];
  char canonical[PATH_MAX]; if (realpath(root.fileSystemRepresentation, canonical)) root = [NSString stringWithUTF8String:canonical];
  NSString* path = [root stringByAppendingPathComponent:[@"Space-" stringByAppendingString:[NSString stringWithUTF8String:profile.c_str()]]];
  CefString(&settings.cache_path) = path.UTF8String; settings.persist_session_cookies = true;
  return contexts[profile] = CefRequestContext::CreateContext(settings, nullptr);
}
void External(const CefString& value) {
  NSString* text = [NSString stringWithUTF8String:value.ToString().c_str()]; NSURL* url = [NSURL URLWithString:text];
  if (![@[@"mailto", @"tel"] containsObject:url.scheme.lowercaseString] || host.window.attachedSheet) return;
  NSAlert* alert = [[NSAlert alloc] init]; alert.messageText = [url.scheme isEqualToString:@"mailto"] ? @"Open Mail?" : @"Open your calling app?";
  alert.informativeText = [text substringToIndex:MIN(text.length, 300)]; [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Open"];
  [alert beginSheetModalForWindow:host.window completionHandler:^(NSModalResponse response) { if (response == NSAlertSecondButtonReturn) [[NSWorkspace sharedWorkspace] openURL:url]; }];
}
void Publish(const std::string& id) {
  CEF_REQUIRE_UI_THREAD();
  auto found = pages.find(id); if (found == pages.end()) return;
  auto& page = found->second;
  DerivativeUpdateTab(id.c_str(), page.title.c_str(), page.url.c_str(), page.loading, page.back, page.forward);
}
void FinishIfClosed() {
  if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Close status: %zu pages, quitting=%d\n", pages.size(), quitting);
  if (quitting && pages.empty() && !exiting) {
    exiting = true;
    DerivativeFinishQuit();
    downloads.clear(); contexts.clear();
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native window closed; requesting loop exit\n");
    CefPostTask(TID_UI, new QuitTask());
  }
}
class BrowserClient final : public CefClient, public CefLifeSpanHandler,
    public CefDisplayHandler, public CefLoadHandler, public CefKeyboardHandler,
    public CefRequestHandler, public CefDownloadHandler, public CefJSDialogHandler, public CefFocusHandler, public CefPermissionHandler {
 public:
  explicit BrowserClient(std::string id) : id_(std::move(id)) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString& origin, uint32_t permissions, CefRefPtr<CefMediaAccessCallback> callback) override {
    const uint32_t supported = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
    if (!IsWebsite(origin) || (permissions & ~supported) || host.window.attachedSheet) { callback->Cancel(); return true; }
    NSAlert* alert = [[NSAlert alloc] init]; alert.messageText = @"Website permission";
    alert.informativeText = [NSString stringWithFormat:@"%s wants to use your %@.", origin.ToString().c_str(), (permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) ? ((permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) ? @"camera and microphone" : @"camera") : @"microphone"];
    [alert addButtonWithTitle:@"Don't Allow"]; [alert addButtonWithTitle:@"Allow Once"];
    [alert beginSheetModalForWindow:host.window completionHandler:^(NSModalResponse response) { callback->Continue(response == NSAlertSecondButtonReturn ? permissions : 0); }];
    return true;
  }
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t, const CefString& origin, uint32_t permissions, CefRefPtr<CefPermissionPromptCallback> callback) override {
    const uint32_t supported = CEF_PERMISSION_TYPE_GEOLOCATION | CEF_PERMISSION_TYPE_NOTIFICATIONS | CEF_PERMISSION_TYPE_CLIPBOARD;
    if (!IsWebsite(origin) || (permissions & ~supported) || host.window.attachedSheet) { callback->Continue(CEF_PERMISSION_RESULT_DENY); return true; }
    NSString* capability = (permissions & CEF_PERMISSION_TYPE_GEOLOCATION) ? @"your location" : (permissions & CEF_PERMISSION_TYPE_NOTIFICATIONS) ? @"notifications" : @"the clipboard";
    NSAlert* alert = [[NSAlert alloc] init]; alert.messageText = @"Website permission"; alert.informativeText = [NSString stringWithFormat:@"%s wants access to %@.", origin.ToString().c_str(), capability];
    [alert addButtonWithTitle:@"Don't Allow"]; [alert addButtonWithTitle:@"Allow Once"];
    [alert beginSheetModalForWindow:host.window completionHandler:^(NSModalResponse response) { callback->Continue(response == NSAlertSecondButtonReturn ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY); }];
    return true;
  }
  void OnGotFocus(CefRefPtr<CefBrowser>) override { if (selected != id_ && Visible(id_)) DerivativePageFocused(id_.c_str()); }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    auto& page = pages.at(id_); page.browser = browser;
    page.view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    page.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    DerivativeLayoutPages();
    if (selected == id_) browser->GetHost()->SetFocus(true);
    Publish(id_);
    if (quitting || page.closing) browser->GetHost()->CloseBrowser(false);
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Closing native tab %s\n", id_.c_str());
    // Each tab is an embedded view. Closing one must not close the parent window.
    const auto id = id_;
    const int closingBrowser = browser->GetIdentifier();
    dispatch_async(dispatch_get_main_queue(), ^{
      @autoreleasepool {
        auto found = pages.find(id);
        if (found != pages.end() && found->second.browser && found->second.browser->GetIdentifier() == closingBrowser) {
          NSView* view = found->second.view;
          [view.window makeFirstResponder:nil];
          [view removeFromSuperview];
          found->second.view = nil;
        }
      }
    });
    return true;
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Destroyed native tab %s\n", id_.c_str());
    auto found = pages.find(id_);
    const bool preserve = found != pages.end() && found->second.preserve;
    pages.erase(id_);
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native tab removed; preserve=%d\n", preserve);
    if (!preserve) DerivativeTabClosed(id_.c_str());
    FinishIfClosed();
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>, const CefString&, bool is_reload,
      CefRefPtr<CefJSDialogCallback> callback) override {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = is_reload ? @"Reload this page?" : @"Leave this page?";
    alert.informativeText = @"Changes you made may not be saved.";
    [alert addButtonWithTitle:is_reload ? @"Reload" : @"Leave"];
    [alert addButtonWithTitle:@"Stay"];
    const auto id = id_;
    [alert beginSheetModalForWindow:host.window completionHandler:^(NSModalResponse response) {
      const bool allow = response == NSAlertFirstButtonReturn;
      if (!allow) {
        auto found = pages.find(id);
        if (found != pages.end()) { found->second.closing = false; found->second.preserve = false; }
        DerivativeCancelTabClose(id.c_str());
        if (quitting) { quitting = false; DerivativeCancelQuit(); }
      }
      callback->Continue(allow, CefString());
    }];
    return true;
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int,
      const CefString& url, const CefString&, WindowOpenDisposition, bool,
      const CefPopupFeatures&, CefWindowInfo&, CefRefPtr<CefClient>&,
      CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    if (IsWebsite(url)) DerivativeOpenPopup(id_.c_str(), url.ToString().c_str()); else External(url);
    return true;
  }
  void OnFullscreenModeChange(CefRefPtr<CefBrowser>, bool fullscreen) override { DerivativeWebsiteFullscreen(fullscreen); }
  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) override {
    pages.at(id_).title = title.ToString(); Publish(id_);
  }
  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (frame->IsMain()) { pages.at(id_).url = url.ToString(); Publish(id_); }
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) override {
    auto& page = pages.at(id_); page.loading = loading; page.back = back; page.forward = forward;
    if (auto entry = browser->GetHost()->GetVisibleNavigationEntry()) {
      page.url = entry->GetURL().ToString();
      if (!entry->GetTitle().empty()) page.title = entry->GetTitle().ToString();
    }
    Publish(id_);
  }
  void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, ErrorCode code,
      const CefString& text, const CefString&) override {
    if (frame->IsMain() && code != ERR_ABORTED) DerivativeTabError(id_.c_str(), text.ToString().c_str());
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request, bool, bool) override {
    const bool blocked = frame->IsMain() && request->GetURL() != "about:blank" && !IsWebsite(request->GetURL());
    if (blocked) External(request->GetURL());
    return blocked;
  }
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser>, TerminationStatus, int, const CefString&) override {
    DerivativeTabError(id_.c_str(), "This page stopped responding. Reload to give it a fresh start.");
  }
  bool CanDownload(CefRefPtr<CefBrowser>, const CefString&, const CefString&) override {
    return true;
  }
  bool OnBeforeDownload(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem>, const CefString& name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
    NSString* directory = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_TEST_DIRECTORY"];
    if (directory) {
      directory = [directory stringByAppendingPathComponent:@"downloads"];
      [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
      NSString* filename = [[NSString stringWithUTF8String:name.ToString().c_str()] lastPathComponent];
      callback->Continue([directory stringByAppendingPathComponent:filename].UTF8String, false);
    } else callback->Continue(CefString(), true);
    return true;
  }
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) override {
    const std::string id = std::to_string(browser->GetIdentifier())+"-"+std::to_string(item->GetId());
    const bool hasPath = !item->GetFullPath().empty();
    if (item->IsInProgress()) {
      downloads[id] = callback;
      if (hasPath) readyDownloads.insert(id);
      if (hasPath && cancelDownloads.erase(id)) CefPostTask(TID_UI, new CancelDownloadTask(callback));
    } else { downloads.erase(id); readyDownloads.erase(id); cancelDownloads.erase(id); }
    const char* status = item->IsComplete() ? "completed" : item->IsCanceled() ? "cancelled" : item->IsInProgress() ? (hasPath ? "progressing" : "choosing") : "interrupted";
    DerivativeDownloadUpdate(id.c_str(), item->GetSuggestedFileName().ToString().c_str(), item->GetFullPath().ToString().c_str(), status, item->GetReceivedBytes(), item->GetTotalBytes());
  }
  bool OnPreKeyEvent(CefRefPtr<CefBrowser>, const CefKeyEvent& event, CefEventHandle, bool*) override {
    const auto flags = event.modifiers;
    const int code = event.windows_key_code;
    if (event.type == KEYEVENT_KEYUP && code == 17) { DerivativeShortcut(1110); return false; }
    if (event.type == KEYEVENT_RAWKEYDOWN && (flags & EVENTFLAG_CONTROL_DOWN) && !(flags & (EVENTFLAG_COMMAND_DOWN | EVENTFLAG_ALT_DOWN)) && code == 9) { DerivativeShortcut(flags & EVENTFLAG_SHIFT_DOWN ? 1101 : 1100); return true; }
    if (event.type == KEYEVENT_RAWKEYDOWN && (flags & EVENTFLAG_COMMAND_DOWN) && !(flags & EVENTFLAG_CONTROL_DOWN)) {
      if ((flags & EVENTFLAG_ALT_DOWN) && !(flags & EVENTFLAG_SHIFT_DOWN) && code >= 37 && code <= 40) { DerivativeShortcut(1200+code-37); return true; }
      if ((flags & EVENTFLAG_SHIFT_DOWN) && !(flags & EVENTFLAG_ALT_DOWN)) {
        int action = code == 'T' ? 1102 : code == 'C' ? 1103 : code == 'R' ? 1104 : code == 219 ? 1105 : code == 221 ? 1106 : 0;
        if (action) { DerivativeShortcut(action); return true; }
      }
    }
    if (event.type == KEYEVENT_RAWKEYDOWN && (event.modifiers & EVENTFLAG_CONTROL_DOWN) && !(event.modifiers & (EVENTFLAG_COMMAND_DOWN | EVENTFLAG_ALT_DOWN | EVENTFLAG_SHIFT_DOWN)) && event.windows_key_code >= '1' && event.windows_key_code <= '9') {
      DerivativeShortcut(1001+event.windows_key_code-'1'); return true;
    }
    if (event.type != KEYEVENT_RAWKEYDOWN || !(event.modifiers & EVENTFLAG_COMMAND_DOWN) ||
        (event.modifiers & (EVENTFLAG_CONTROL_DOWN | EVENTFLAG_ALT_DOWN | EVENTFLAG_SHIFT_DOWN))) return false;
    const int key = event.windows_key_code;
    if (key == 'T' || key == 'L' || key == 'S' || key == 'R' || key == 'W' || key == 'Q' || key == 'D' || key == 188 || key == 219 || key == 221 || (key >= '1' && key <= '9')) {
      DerivativeShortcut(key); return true;
    }
    return false;
  }
 private:
  const std::string id_;
  IMPLEMENT_REFCOUNTING(BrowserClient);
};

class BrowserApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
  void OnContextInitialized() override {
    CEF_REQUIRE_UI_THREAD(); host = (__bridge NSView*)DerivativeCreateWindow();
    const auto command = CefCommandLine::GetGlobalCommandLine();
    const std::string url = command->HasSwitch("url") && IsWebsite(command->GetSwitchValue("url")) ? command->GetSwitchValue("url").ToString() : "";
    DerivativeReady(url.c_str());
  }
 private:
  IMPLEMENT_REFCOUNTING(BrowserApp);
};
} // namespace

extern "C" void DerivativeCreatePage(const char* id, const char* space, const char* url) {
  CEF_REQUIRE_UI_THREAD();
  if (pages.count(id) || !IsWebsite(url) || quitting) return;
  const std::string profile(space);
  if (profile.empty() || profile.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-") != std::string::npos) return;
  if (!Context(profile)) return;
  auto& page = pages[id]; page.space = space; page.url = url; page.title = url; page.loading = true;
  CefWindowInfo info;
  info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(host), CefRect(0, 0, host.bounds.size.width, host.bounds.size.height));
  info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings;
  if (!CefBrowserHost::CreateBrowser(info, new BrowserClient(id), url, settings, nullptr, contexts.at(profile))) {
    pages.erase(id); DerivativeTabError(id, "Unable to open this page. Please try again.");
  }
}
extern "C" void DerivativeLayoutPages() {
  CEF_REQUIRE_UI_THREAD();
  for (auto& [key, page] : pages) {
    if (!page.view) continue;
    if (!Visible(key)) { page.view.hidden = YES; [page.view removeFromSuperview]; continue; }
    if (page.view.superview != host) [host addSubview:page.view];
    NSRect frame = host.bounds;
    if (!splitFirst.empty() && !splitSecond.empty()) {
      const CGFloat left = (frame.size.width-6)*splitRatio;
      if (key == splitFirst) frame.size.width = left;
      else { frame.origin.x = left+6; frame.size.width -= left+6; }
    }
    page.view.frame = frame;
    page.view.autoresizingMask = splitFirst.empty() ? NSViewWidthSizable|NSViewHeightSizable : NSViewNotSizable;
    page.view.hidden = NO;
  }
}
extern "C" void DerivativeSetSplit(const char* first, const char* second, double ratio) {
  splitFirst = first; splitSecond = second; splitRatio = std::max(0.2, std::min(0.8, ratio));
  DerivativeLayoutPages();
}
extern "C" void DerivativeSelectPage(const char* id) {
  CEF_REQUIRE_UI_THREAD(); selected = id; DerivativeLayoutPages();
  for (auto& [key, page] : pages) if (page.browser) page.browser->GetHost()->SetFocus(key == selected);
}
extern "C" void DerivativeClosePage(const char* id) {
  auto found = pages.find(id);
  if (found == pages.end()) { DerivativeTabClosed(id); return; }
  if (!found->second.closing) { found->second.closing = true; if (found->second.browser) found->second.browser->GetHost()->CloseBrowser(false); }
}
extern "C" int DerivativePageCount() { return static_cast<int>(pages.size()); }
extern "C" void DerivativeRequestQuit() {
  if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native quit requested: %zu pages\n", pages.size());
  if (quitting) return;
  quitting = true;
  std::vector<CefRefPtr<CefBrowser>> closing;
  for (auto& [id, page] : pages) {
    if (!page.closing) { page.preserve = true; page.closing = true; if (page.browser) closing.push_back(page.browser); }
  }
  for (auto browser : closing) browser->GetHost()->CloseBrowser(false);
  FinishIfClosed();
}
extern "C" void DerivativeNavigate(const char* url) { if (auto page = Active(); page && IsWebsite(url)) page->GetMainFrame()->LoadURL(url); }
extern "C" void DerivativeBack() { if (auto page = Active(); page && page->CanGoBack()) page->GoBack(); }
extern "C" void DerivativeForward() { if (auto page = Active(); page && page->CanGoForward()) page->GoForward(); }
extern "C" void DerivativeReload() { if (auto page = Active()) page->Reload(); }
extern "C" void DerivativeStop() { if (auto page = Active()) page->StopLoad(); }
extern "C" void DerivativeHardReload() { if (auto page = Active()) page->ReloadIgnoreCache(); }
extern "C" void DerivativeCancelDownload(const char* id) {
  auto found = downloads.find(id);
  if (found == downloads.end()) return;
  if (readyDownloads.count(id)) CefPostTask(TID_UI, new CancelDownloadTask(found->second));
  else cancelDownloads.insert(id);
}
extern "C" void DerivativeClearData(const char* target) {
  NSString* root = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_USER_DATA"];
  if (!root) root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Derivative Native Prototype"];
  for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) if ([name hasPrefix:@"Space-"]) Context([[name substringFromIndex:6] UTF8String]);
  for (auto& [id, context] : contexts) {
    if (std::string(target) == "cache") context->ClearHttpCache(new Completion());
    else if (std::string(target) == "cookies") context->GetCookieManager(nullptr)->DeleteCookies(CefString(), CefString(), nullptr);
  }
}
extern "C" void DerivativeFocusPage() { if (auto page = Active()) page->GetHost()->SetFocus(true); }

@interface DerivativeApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation DerivativeApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent*)event { CefScopedSendingEvent scope; [super sendEvent:event]; }
- (void)terminate:(id)sender {
  if (host.window) [host.window performClose:sender];
  else DerivativeRequestQuit();
}
@end

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader library;
  if (!library.LoadInMain()) return 1;
  @autoreleasepool {
    [DerivativeApplication sharedApplication];
    [NSApp setActivationPolicy:(getenv("DERIVATIVE_NATIVE_AUTOMATED") && std::string(getenv("DERIVATIVE_NATIVE_AUTOMATED")) == "1") ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular];
    CefSettings settings;
    NSString* profile = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_USER_DATA"];
    if (!profile) profile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Derivative Native Prototype"];
    [[NSFileManager defaultManager] createDirectoryAtPath:profile withIntermediateDirectories:YES attributes:nil error:nil];
    char canonical[PATH_MAX];
    if (realpath(profile.fileSystemRepresentation, canonical)) profile = [NSString stringWithUTF8String:canonical];
    CefString(&settings.root_cache_path) = profile.UTF8String;
    CefString(&settings.cache_path) = [profile stringByAppendingPathComponent:@"Default"].UTF8String;
    CefString(&settings.log_file) = [profile stringByAppendingPathComponent:@"chromium.log"].UTF8String;
    CefString(&settings.user_agent_product) = "Derivative/0.1";
    settings.log_severity = LOGSEVERITY_WARNING;
    if (!CefInitialize(CefMainArgs(argc, argv), settings, new BrowserApp(), nullptr)) return CefGetExitCode();
    CefRunMessageLoop();
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native event loop returned\n");
    downloads.clear(); contexts.clear(); host = nil;
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native contexts released\n");
    CefShutdown();
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native shutdown completed\n");
  }
  return 0;
}
