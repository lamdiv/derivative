#import "../Sources/BrowserKeychain.h"
#include <cassert>
#include <initializer_list>
using namespace DerivativeKeychain;

struct FakeKeychain : Backend {
  int reads = 0, adds = 0;
  OSStatus read_status = errSecSuccess, add_status = errSecSuccess;
  NSData* copied = nil;
  OSStatus ReadLegacy(NSData** secret) override {
    ++reads; *secret = [@"synthetic-fixture-key" dataUsingEncoding:NSUTF8StringEncoding]; return read_status;
  }
  OSStatus Add(const Identity&, NSData* secret) override { ++adds; copied = secret; return add_status; }
};
NSString* temporaryProfile() {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
  return path;
}
void legacy(NSString* path) { assert([[@"{}" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[path stringByAppendingPathComponent:@"Local State"] atomically:YES]); }
int main() { @autoreleasepool {
  NSString* error = nil; Identity identity;
  {
    NSString* root = temporaryProfile(); FakeKeychain backend;
    assert(Prepare(root, false, false, backend, identity, &error));
    assert([identity.service isEqual:@"Derivative Safe Storage"] && backend.reads == 0 && backend.adds == 0);
    NSString* account = identity.account;
    legacy(root); // Subsequent startup must use its saved identity, never read the shared item again.
    assert(Prepare(root, false, false, backend, identity, &error));
    assert([identity.account isEqual:account] && backend.reads == 0);
    assert(!Prepare(root, true, false, backend, identity, &error)); // Don't silently change an encrypted profile's key.
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
  }
  {
    NSString* root = temporaryProfile(); legacy(root); FakeKeychain backend;
    assert(Prepare(root, false, false, backend, identity, &error));
    assert(backend.reads == 1 && backend.adds == 1);
    assert([backend.copied isEqual:[@"synthetic-fixture-key" dataUsingEncoding:NSUTF8StringEncoding]]);
    NSString* marker = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"keychain-identity.json"] encoding:NSUTF8StringEncoding error:nil];
    assert([marker rangeOfString:@"synthetic-fixture-key"].location == NSNotFound);
    assert(Prepare(root, false, false, backend, identity, &error) && backend.reads == 1 && backend.adds == 1);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
  }
  for (bool deny_read : {false, true}) {
    NSString* root = temporaryProfile(); legacy(root); FakeKeychain backend;
    if (deny_read) backend.read_status = errSecAuthFailed; else backend.add_status = errSecAuthFailed;
    assert(!Prepare(root, false, false, backend, identity, &error));
    assert(![NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"keychain-identity.json"]]);
    assert([NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"Local State"]]);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
  }
  {
    NSString* root = temporaryProfile(); FakeKeychain backend;
    assert(Prepare(root, true, false, backend, identity, &error));
    assert([identity.service isEqual:@"Derivative Development Safe Storage"]);
    [@"not-json" writeToFile:[root stringByAppendingPathComponent:@"keychain-identity.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    assert(!Prepare(root, true, false, backend, identity, &error));
    assert(backend.reads == 0 && backend.adds == 0);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
  }
  {
    NSString* root = temporaryProfile(); legacy(root); FakeKeychain backend;
    assert(Prepare(root, true, true, backend, identity, &error));
    assert(backend.reads == 0 && backend.adds == 0); // Existing mock-keychain fixtures never touch the real Keychain.
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
  }
  NSLog(@"PASS: scoped Keychain identity, one-time key-preserving migration, denied-access safety, development isolation, and corrupt-marker guards.");
} }
