// Portions copyright (c) 2013 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// macOS event-loop setup adapts cefsimple under the BSD license in
// ../ThirdParty/CEF-LICENSE.txt.
#import <AppKit/AppKit.h>
#include "Bridge.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

namespace {
CefRefPtr<CefBrowser> page;
std::string page_title = "New tab", page_url;
bool page_loading = false, page_back = false, page_forward = false;

void Publish() {
  CEF_REQUIRE_UI_THREAD();
  DerivativeUpdatePage(page_title.c_str(), page_url.c_str(), page_loading, page_back, page_forward);
}
bool IsWebsite(const CefString& value) {
  CefURLParts parts;
  if (!CefParseURL(value, parts)) return false;
  const std::string scheme = CefString(&parts.scheme);
  return scheme == "http" || scheme == "https";
}

class BrowserClient final : public CefClient, public CefLifeSpanHandler,
    public CefDisplayHandler, public CefLoadHandler, public CefKeyboardHandler,
    public CefRequestHandler, public CefDownloadHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    page = browser;
    NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    Publish();
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    page = nullptr;
    CefQuitMessageLoop();
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int,
      const CefString&, const CefString&, WindowOpenDisposition, bool,
      const CefPopupFeatures&, CefWindowInfo&, CefRefPtr<CefClient>&,
      CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    // The comparison prototype intentionally owns exactly one page.
    DerivativeShowError("Popup windows are not supported in this prototype.");
    return true;
  }
  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) override {
    page_title = title.ToString(); Publish();
  }
  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (frame->IsMain()) { page_url = url.ToString(); Publish(); }
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) override {
    page_loading = loading; page_back = back; page_forward = forward;
    if (auto entry = browser->GetHost()->GetVisibleNavigationEntry()) {
      page_url = entry->GetURL().ToString();
      if (!entry->GetTitle().empty()) page_title = entry->GetTitle().ToString();
    }
    Publish();
  }
  void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, ErrorCode code,
      const CefString& text, const CefString&) override {
    if (frame->IsMain() && code != ERR_ABORTED) DerivativeShowError(text.ToString().c_str());
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request, bool, bool) override {
    return frame->IsMain() && request->GetURL() != "about:blank" && !IsWebsite(request->GetURL());
  }
  bool CanDownload(CefRefPtr<CefBrowser>, const CefString&, const CefString&) override {
    DerivativeShowError("Downloads are not supported in this prototype.");
    return false;
  }
  bool OnPreKeyEvent(CefRefPtr<CefBrowser>, const CefKeyEvent& event, CefEventHandle, bool*) override {
    if (event.type != KEYEVENT_RAWKEYDOWN || !(event.modifiers & EVENTFLAG_COMMAND_DOWN) ||
        (event.modifiers & (EVENTFLAG_CONTROL_DOWN | EVENTFLAG_ALT_DOWN | EVENTFLAG_SHIFT_DOWN))) return false;
    const int key = event.windows_key_code;
    if (key == 'T' || key == 'L' || key == 'S' || key == 'R') { DerivativeShortcut(key); return true; }
    return false;
  }
 private:
  IMPLEMENT_REFCOUNTING(BrowserClient);
};

class BrowserApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
  void OnContextInitialized() override {
    CEF_REQUIRE_UI_THREAD();
    NSView* host = (__bridge NSView*)DerivativeCreateWindow();
    CefWindowInfo info;
    info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(host), CefRect(0, 0, host.bounds.size.width, host.bounds.size.height));
    info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    CefBrowserSettings settings;
    std::string url = "about:blank";
    auto command = CefCommandLine::GetGlobalCommandLine();
    if (command->HasSwitch("url") && IsWebsite(command->GetSwitchValue("url"))) url = command->GetSwitchValue("url");
    page_url = url == "about:blank" ? "" : url;
    if (!CefBrowserHost::CreateBrowserSync(info, new BrowserClient(), url, settings, nullptr, nullptr)) {
      fprintf(stderr, "Unable to create Chromium page.\n"); CefQuitMessageLoop();
    }
  }
 private:
  IMPLEMENT_REFCOUNTING(BrowserApp);
};
} // namespace

extern "C" void DerivativeNavigate(const char* url) {
  CEF_REQUIRE_UI_THREAD();
  if (page && IsWebsite(url)) page->GetMainFrame()->LoadURL(url);
}
extern "C" void DerivativeBack() { if (page && page->CanGoBack()) page->GoBack(); }
extern "C" void DerivativeForward() { if (page && page->CanGoForward()) page->GoForward(); }
extern "C" void DerivativeReload() { if (page) page->Reload(); }
extern "C" bool DerivativeCanCloseBrowser() { return !page || page->GetHost()->TryCloseBrowser(); }
extern "C" void DerivativeFocusPage() { if (page) page->GetHost()->SetFocus(true); }

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
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    CefSettings settings;
    NSString* profile = NSProcessInfo.processInfo.environment[@"DERIVATIVE_NATIVE_USER_DATA"];
    if (!profile) profile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Derivative Native Prototype"];
    CefString(&settings.root_cache_path) = profile.UTF8String;
    CefString(&settings.cache_path) = [profile stringByAppendingPathComponent:@"Default"].UTF8String;
    CefString(&settings.log_file) = [profile stringByAppendingPathComponent:@"chromium.log"].UTF8String;
    CefString(&settings.user_agent_product) = "DerivativeNative/0.1";
    settings.log_severity = LOGSEVERITY_WARNING;
    if (!CefInitialize(CefMainArgs(argc, argv), settings, new BrowserApp(), nullptr)) return CefGetExitCode();
    CefRunMessageLoop();
    CefShutdown();
  }
  return 0;
}
