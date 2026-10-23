#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
void DerivativeNavigate(const char* url);
void DerivativeBack(void);
void DerivativeForward(void);
void DerivativeReload(void);
bool DerivativeCanCloseBrowser(void);
void DerivativeFocusPage(void);
void* DerivativeCreateWindow(void);
void DerivativeUpdatePage(const char* title, const char* url, bool loading, bool back, bool forward);
void DerivativeShowError(const char* message);
void DerivativeShortcut(int key);
#ifdef __cplusplus
}
#endif
