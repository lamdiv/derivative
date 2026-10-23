// Included by Browser.mm inside its private namespace.
enum WebMenuCommand {
  OpenLink = MENU_ID_USER_FIRST+1, SplitLink, SaveLink, CopyLink,
  OpenImage, SaveImage, CopyImage, CopyImageAddress, SearchImage,
  SearchSelection, InspectElement, OpenMedia, SaveMedia, CopyMediaAddress
};
struct WebMenuTarget {
  std::string opener, link, source, selection;
  int x = 0, y = 0;
};
WebMenuTarget lastMenuTarget;
int menuGeneration = 0;
std::vector<std::pair<int, std::string>> lastMenuItems;
void CopyAddress(const std::string& value) {
  NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
  [pasteboard clearContents];
  [pasteboard setString:[NSString stringWithUTF8String:value.c_str()] forType:NSPasteboardTypeString];
}
NSPasteboard* ImageClipboard() {
  if (getenv("DERIVATIVE_NATIVE_AUTOMATED") && getenv("DERIVATIVE_NATIVE_TEST_DIRECTORY")) {
    static NSPasteboard* isolated = [NSPasteboard pasteboardWithUniqueName]; return isolated;
  }
  return NSPasteboard.generalPasteboard;
}
class CopyWebImage final : public CefDownloadImageCallback {
 public:
  void OnDownloadImageFinished(const CefString&, int, CefRefPtr<CefImage> image) override {
    if (!image || image->IsEmpty()) { DerivativeShowError("This image could not be copied."); return; }
    int width = 0, height = 0;
    auto png = image->GetAsPNG(1.0, true, width, height);
    if (!png) { DerivativeShowError("This image could not be copied."); return; }
    NSMutableData* data = [NSMutableData dataWithLength:png->GetSize()];
    png->GetData(data.mutableBytes, data.length, 0);
    [ImageClipboard() clearContents];
    [ImageClipboard() setData:data forType:NSPasteboardTypePNG];
  }
 private:
  IMPLEMENT_REFCOUNTING(CopyWebImage);
};
bool CanSaveMedia(const std::string& url) { return IsWebsite(url) || url.starts_with("data:") || url.starts_with("blob:"); }
bool ExecuteWebMenu(CefRefPtr<CefBrowser> browser, const WebMenuTarget& target, int command) {
  switch (command) {
    case OpenLink: case SplitLink:
      if (IsWebsite(target.link)) DerivativeContextAction(target.opener.c_str(), target.link.c_str(), command == SplitLink ? "split" : "open");
      return true;
    case OpenImage: case OpenMedia:
      if (IsWebsite(target.source)) DerivativeContextAction(target.opener.c_str(), target.source.c_str(), "open");
      return true;
    case SaveLink: case SaveImage: case SaveMedia: {
      const auto& url = command == SaveLink ? target.link : target.source;
      if (CanSaveMedia(url)) browser->GetHost()->StartDownload(url);
      return true;
    }
    case CopyLink: CopyAddress(target.link); return true;
    case CopyImageAddress: case CopyMediaAddress: CopyAddress(target.source); return true;
    case CopyImage:
      if (CanSaveMedia(target.source)) browser->GetHost()->DownloadImage(target.source, false, 0, false, new CopyWebImage());
      return true;
    case SearchImage:
      if (IsWebsite(target.source)) {
        const auto url = "https://lens.google.com/uploadbyurl?url="+CefURIEncode(target.source, false).ToString();
        DerivativeContextAction(target.opener.c_str(), url.c_str(), "open");
      }
      return true;
    case SearchSelection:
      if (!target.selection.empty()) DerivativeContextAction(target.opener.c_str(), target.selection.c_str(), "search");
      return true;
    case InspectElement: {
      CefWindowInfo info; CefBrowserSettings settings;
      info.hidden = getenv("DERIVATIVE_NATIVE_AUTOMATED") != nullptr;
      browser->GetHost()->ShowDevTools(info, nullptr, settings, CefPoint(target.x, target.y));
      return true;
    }
    default: return false;
  }
}
class WebContextMenus : public CefContextMenuHandler {
 public:
  explicit WebContextMenus(std::string opener) : opener_(std::move(opener)) {}
  void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> menu) override {
    const auto target = Target(params);
    // Keep Chromium's editing/spelling/selection actions. Replace the bare
    // navigation menu when the click belongs to a link, image, or media item.
    const bool contextual = !target.link.empty() || params->GetMediaType() != CM_MEDIATYPE_NONE;
    if (contextual && !params->IsEditable() && target.selection.empty()) menu->Clear();
    auto separator = [&] { if (menu->GetCount() && menu->GetTypeAt(menu->GetCount()-1) != MENUITEMTYPE_SEPARATOR) menu->AddSeparator(); };
    if (!target.link.empty()) {
      separator();
      if (IsWebsite(target.link)) {
        menu->AddItem(OpenLink, "Open Link in New Tab");
        menu->AddItem(SplitLink, "Open Link in Split View");
        menu->AddItem(SaveLink, "Save Link As…");
      }
      menu->AddItem(CopyLink, "Copy Link Address");
    }
    if (params->GetMediaType() == CM_MEDIATYPE_IMAGE && !target.source.empty()) {
      separator();
      if (IsWebsite(target.source)) menu->AddItem(OpenImage, "Open Image in New Tab");
      if (CanSaveMedia(target.source)) {
        menu->AddItem(SaveImage, "Save Image As…");
        if (params->HasImageContents()) menu->AddItem(CopyImage, "Copy Image");
      }
      menu->AddItem(CopyImageAddress, "Copy Image Address");
      if (IsWebsite(target.source)) menu->AddItem(SearchImage, "Search Google for Image");
    } else if ((params->GetMediaType() == CM_MEDIATYPE_VIDEO || params->GetMediaType() == CM_MEDIATYPE_AUDIO) && !target.source.empty()) {
      separator();
      if (IsWebsite(target.source)) menu->AddItem(OpenMedia, "Open Media in New Tab");
      if (CanSaveMedia(target.source)) menu->AddItem(SaveMedia, "Save Media As…");
      menu->AddItem(CopyMediaAddress, "Copy Media Address");
    }
    if (!target.selection.empty()) { separator(); menu->AddItem(SearchSelection, "Search the Web for Selection"); }
    if (!contextual && !params->IsEditable() && menu->GetIndexOf(MENU_ID_RELOAD) < 0) menu->AddItem(MENU_ID_RELOAD, "Reload");
    separator(); menu->AddItem(InspectElement, "Inspect");
    if (getenv("DERIVATIVE_NATIVE_TEST_DIRECTORY")) {
      ++menuGeneration; lastMenuTarget = target; lastMenuItems.clear();
      for (size_t i = 0; i < menu->GetCount(); ++i) if (menu->GetTypeAt(i) != MENUITEMTYPE_SEPARATOR) lastMenuItems.emplace_back(menu->GetCommandIdAt(i), menu->GetLabelAt(i).ToString());
    }
  }
  bool RunContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams>, CefRefPtr<CefMenuModel>, CefRefPtr<CefRunContextMenuCallback> callback) override {
    if (getenv("DERIVATIVE_NATIVE_AUTOMATED")) { callback->Cancel(); return true; }
    return false;
  }
  bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params, int command, EventFlags) override {
    return ExecuteWebMenu(browser, Target(params), command);
  }
 private:
  WebMenuTarget Target(CefRefPtr<CefContextMenuParams> params) const {
    return {opener_, params->GetLinkUrl().ToString(), params->GetSourceUrl().ToString(), params->GetSelectionText().ToString(), params->GetXCoord(), params->GetYCoord()};
  }
  std::string opener_;
};
