// Copyright (c) 2013 The Chromium Embedded Framework Authors.
// Sandbox/bootstrap sequence adapts the CEF macOS helper example under the
// BSD license in ../ThirdParty/CEF-LICENSE.txt.
#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"
int main(int argc, char* argv[]) {
  CefScopedSandboxContext sandbox;
  if (!sandbox.Initialize(argc, argv)) return 1;
  CefScopedLibraryLoader library;
  if (!library.LoadInHelper()) return 1;
  return CefExecuteProcess(CefMainArgs(argc, argv), nullptr, nullptr);
}
