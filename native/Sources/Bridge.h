#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
void DerivativeCreatePage(const char* id, const char* space, const char* url);
void DerivativeSelectPage(const char* id);
void DerivativeClosePage(const char* id);
void DerivativeRequestQuit(void);
int DerivativePageCount(void);
void DerivativeNavigate(const char* url);
void DerivativeBack(void);
void DerivativeForward(void);
void DerivativeReload(void);
void DerivativeFocusPage(void);
void DerivativeStop(void);
void DerivativeHardReload(void);
void DerivativeSetSplit(const char* first, const char* second, double ratio);
void DerivativeLayoutPages(void);
void DerivativeClearData(const char* target);
void DerivativeCancelDownload(const char* id);
void DerivativeDownloadUpdate(const char* id, const char* name, const char* path, const char* status, double received, double total);
void DerivativeCancelTabClose(const char* id);
void DerivativePageFocused(const char* id);
void DerivativeWebsiteFullscreen(bool fullscreen);
void* DerivativeCreateWindow(void);
void DerivativeReady(const char* startup_url);
void DerivativeUpdateTab(const char* id, const char* title, const char* url, bool loading, bool back, bool forward);
void DerivativeTabClosed(const char* id);
void DerivativeFinishQuit(void);
void DerivativeCancelQuit(void);
void DerivativeOpenPopup(const char* opener, const char* url);
void DerivativeShowError(const char* message);
void DerivativeTabError(const char* id, const char* message);
void DerivativeShortcut(int key);
#ifdef __cplusplus
}
#endif
