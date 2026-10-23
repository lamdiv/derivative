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
void* DerivativeCreateWindow(void);
void DerivativeReady(const char* startup_url);
void DerivativeUpdateTab(const char* id, const char* title, const char* url, bool loading, bool back, bool forward);
void DerivativeTabClosed(const char* id);
void DerivativeFinishQuit(void);
void DerivativeCancelQuit(void);
void DerivativeOpenPopup(const char* opener, const char* url);
void DerivativeShowError(const char* message);
void DerivativeShortcut(int key);
#ifdef __cplusplus
}
#endif
