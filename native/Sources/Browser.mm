// Portions copyright (c) 2013 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// macOS event-loop setup adapts cefsimple under ../ThirdParty/CEF-LICENSE.txt.
#import <AppKit/AppKit.h>
#include <map>
#include <vector>
#include <limits.h>
#include <stdlib.h>
#include "Bridge.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_parser.h"
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
std::string selected;
bool quitting = false, exiting = false;
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
    contexts.clear();
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native window closed; requesting loop exit\n");
    CefPostTask(TID_UI, new QuitTask());
  }
}
class BrowserClient final : public CefClient, public CefLifeSpanHandler,
    public CefDisplayHandler, public CefLoadHandler, public CefKeyboardHandler,
    public CefRequestHandler, public CefDownloadHandler, public CefJSDialogHandler {
 public:
  explicit BrowserClient(std::string id) : id_(std::move(id)) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    auto& page = pages.at(id_); page.browser = browser;
    page.view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    page.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    page.view.hidden = selected != id_;
    if (selected == id_) browser->GetHost()->SetFocus(true);
    Publish(id_);
    if (quitting || page.closing) browser->GetHost()->CloseBrowser(false);
  }
  bool DoClose(CefRefPtr<CefBrowser>) override {
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Closing native tab %s\n", id_.c_str());
    // Each tab is an embedded view. Closing one must not close the parent window.
    const auto id = id_;
    dispatch_async(dispatch_get_main_queue(), ^{
      @autoreleasepool {
        auto found = pages.find(id);
        if (found != pages.end()) {
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
    if (IsWebsite(url)) DerivativeOpenPopup(id_.c_str(), url.ToString().c_str());
    return true;
  }
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
    if (frame->IsMain() && code != ERR_ABORTED && selected == id_) DerivativeShowError(text.ToString().c_str());
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request, bool, bool) override {
    return frame->IsMain() && request->GetURL() != "about:blank" && !IsWebsite(request->GetURL());
  }
  bool CanDownload(CefRefPtr<CefBrowser>, const CefString&, const CefString&) override {
    DerivativeShowError("Downloads have not been migrated yet."); return false;
  }
  bool OnPreKeyEvent(CefRefPtr<CefBrowser>, const CefKeyEvent& event, CefEventHandle, bool*) override {
    if (event.type == KEYEVENT_RAWKEYDOWN && (event.modifiers & EVENTFLAG_CONTROL_DOWN) && !(event.modifiers & (EVENTFLAG_COMMAND_DOWN | EVENTFLAG_ALT_DOWN | EVENTFLAG_SHIFT_DOWN)) && event.windows_key_code >= '1' && event.windows_key_code <= '9') {
      DerivativeShortcut(1001+event.windows_key_code-'1'); return true;
    }
    if (event.type != KEYEVENT_RAWKEYDOWN || !(event.modifiers & EVENTFLAG_COMMAND_DOWN) ||
        (event.modifiers & (EVENTFLAG_CONTROL_DOWN | EVENTFLAG_ALT_DOWN | EVENTFLAG_SHIFT_DOWN))) return false;
    const int key = event.windows_key_code;
    if (key == 'T' || key == 'L' || key == 'S' || key == 'R' || key == 'W' || key == 'Q' || key == 'D' || (key >= '1' && key <= '9')) {
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
  if (!contexts.count(profile)) {
    CefRequestContextSettings settings;
    const auto command = CefCommandLine::GetGlobalCommandLine();
    NSString* root = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_USER_DATA"];
    if (!root) root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Derivative Native Prototype"];
    char canonical[PATH_MAX];
    if (realpath(root.fileSystemRepresentation, canonical)) root = [NSString stringWithUTF8String:canonical];
    NSString* path = [root stringByAppendingPathComponent:[@"Space-" stringByAppendingString:[NSString stringWithUTF8String:space]]];
    CefString(&settings.cache_path) = path.UTF8String; settings.persist_session_cookies = true;
    contexts[profile] = CefRequestContext::CreateContext(settings, nullptr);
  }
  auto& page = pages[id]; page.space = space; page.url = url; page.title = url; page.loading = true;
  CefWindowInfo info;
  info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(host), CefRect(0, 0, host.bounds.size.width, host.bounds.size.height));
  info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings;
  if (!CefBrowserHost::CreateBrowser(info, new BrowserClient(id), url, settings, nullptr, contexts.at(profile))) {
    pages.erase(id); DerivativeShowError("Unable to create Chromium tab.");
  }
}
extern "C" void DerivativeSelectPage(const char* id) {
  CEF_REQUIRE_UI_THREAD(); selected = id;
  for (auto& [key, page] : pages) {
    page.view.hidden = key != selected;
    if (page.browser) page.browser->GetHost()->SetFocus(key == selected);
  }
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
extern "C" void DerivativeFocusPage() { if (auto page = Active()) page->GetHost()->SetFocus(true); }

@interface DerivativeApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation DerivativeApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent*)event { CefScopedSendingEvent scope; [super sendEvent:event]; }
- (void)terminate:(id)sender { [self.keyWindow performClose:sender]; }
@end

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader library;
  if (!library.LoadInMain()) return 1;
  @autoreleasepool {
    [DerivativeApplication sharedApplication];
    [NSApp setActivationPolicy:getenv("DERIVATIVE_NATIVE_AUTOMATED") ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular];
    CefSettings settings;
    NSString* profile = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_USER_DATA"];
    if (!profile) profile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Derivative Native Prototype"];
    [[NSFileManager defaultManager] createDirectoryAtPath:profile withIntermediateDirectories:YES attributes:nil error:nil];
    char canonical[PATH_MAX];
    if (realpath(profile.fileSystemRepresentation, canonical)) profile = [NSString stringWithUTF8String:canonical];
    CefString(&settings.root_cache_path) = profile.UTF8String;
    CefString(&settings.cache_path) = [profile stringByAppendingPathComponent:@"Default"].UTF8String;
    CefString(&settings.log_file) = [profile stringByAppendingPathComponent:@"chromium.log"].UTF8String;
    CefString(&settings.user_agent_product) = "DerivativeNative/0.1";
    settings.log_severity = LOGSEVERITY_WARNING;
    if (!CefInitialize(CefMainArgs(argc, argv), settings, new BrowserApp(), nullptr)) return CefGetExitCode();
    CefRunMessageLoop();
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native event loop returned\n");
    contexts.clear(); host = nil;
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native contexts released\n");
    CefShutdown();
    if (getenv("DERIVATIVE_NATIVE_TRACE")) fprintf(stderr, "Native shutdown completed\n");
  }
  return 0;
}
