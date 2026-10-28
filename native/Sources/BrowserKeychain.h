#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Each profile owns an item. No secret is written into the profile marker.
// CEF uses the same service/account for its synchronous and async OSCrypt paths.
namespace DerivativeKeychain {
struct Identity { NSString* service = nil; NSString* account = nil; };
struct Backend {
  virtual OSStatus ReadLegacy(NSData** secret) = 0;
  virtual OSStatus Add(const Identity& identity, NSData* secret) = 0;
  virtual ~Backend() = default;
};
struct SystemBackend final : Backend {
  OSStatus ReadLegacy(NSData** secret) override {
    NSDictionary* query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService: @"Chromium Safe Storage",
      (__bridge id)kSecAttrAccount: @"Chromium",
      (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
      (__bridge id)kSecReturnData: @YES};
    CFTypeRef result = nullptr;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess) *secret = CFBridgingRelease(result);
    else if (result) CFRelease(result);
    return status;
  }
  OSStatus Add(const Identity& identity, NSData* secret) override {
    // Default Keychain ACL trusts this signed application, not every app.
    NSDictionary* query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService: identity.service,
      (__bridge id)kSecAttrAccount: identity.account,
      (__bridge id)kSecValueData: secret};
    return SecItemAdd((__bridge CFDictionaryRef)query, nullptr);
  }
};

inline bool DevelopmentBuild() {
  SecCodeRef code = nullptr;
  CFDictionaryRef information = nullptr;
  bool development = true;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess &&
      SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information) == errSecSuccess) {
    NSDictionary* values = (__bridge NSDictionary*)information;
    NSString* team = values[(__bridge id)kSecCodeInfoTeamIdentifier];
    development = ![team isKindOfClass:NSString.class] || team.length == 0;
  }
  if (information) CFRelease(information);
  if (code) CFRelease(code);
  return development;
}

inline bool HasExistingEngineData(NSString* root) {
  NSFileManager* files = NSFileManager.defaultManager;
  if ([files fileExistsAtPath:[root stringByAppendingPathComponent:@"Local State"]]) return true;
  for (NSString* name in [files contentsOfDirectoryAtPath:root error:nil]) {
    if (![name isEqualToString:@"Default"] && ![name hasPrefix:@"Space-"]) continue;
    NSString* profile = [root stringByAppendingPathComponent:name];
    for (NSString* suffix in @[@"Cookies", @"Network/Cookies", @"Preferences"])
      if ([files fileExistsAtPath:[profile stringByAppendingPathComponent:suffix]]) return true;
  }
  return false;
}

inline bool Prepare(NSString* root, bool development, bool mock, Backend& backend,
                    Identity& identity, NSString** failure) {
  NSString* marker = [root stringByAppendingPathComponent:@"keychain-identity.json"];
  NSString* service = development ? @"Derivative Development Safe Storage" : @"Derivative Safe Storage";
  NSString* prefix = development ? @"app.derivative.browser.native.development." : @"app.derivative.browser.native.";
  if ([NSFileManager.defaultManager fileExistsAtPath:marker]) {
    NSData* bytes = [NSData dataWithContentsOfFile:marker];
    id parsed = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
    if (![parsed isKindOfClass:NSDictionary.class]) {
      *failure = @"The browser's Keychain configuration could not be read. Your saved data has not been changed.";
      return false;
    }
    NSDictionary* saved = parsed;
    NSString* account = [saved[@"account"] isKindOfClass:NSString.class] ? saved[@"account"] : @"";
    if (![saved[@"version"] isEqual:@1] || ![saved[@"service"] isEqual:service] ||
        ![account hasPrefix:prefix] || ![[NSUUID alloc] initWithUUIDString:[account substringFromIndex:prefix.length]]) {
      *failure = @"This profile belongs to a different browser signing identity or its Keychain configuration is invalid. Your saved data has not been changed.";
      return false;
    }
    identity = {service, account};
    return true;  // Do not retrieve the secret once here and again inside CEF.
  }
  identity = {service, [prefix stringByAppendingString:NSUUID.UUID.UUIDString]};
  if (!mock && HasExistingEngineData(root)) {
    NSData* secret = nil;
    OSStatus status = backend.ReadLegacy(&secret);
    if (status != errSecSuccess || !secret.length) {
      *failure = @"Derivative couldn't unlock the encryption key for your existing browser data. Unlock your login Keychain and try again. No cookies or encryption keys have been reset.";
      return false;
    }
    // Copy the original key material; changing the label alone would sign users
    // out. Leave the shared item intact for other Chromium applications.
    if (backend.Add(identity, secret) != errSecSuccess) {
      *failure = @"Derivative couldn't create its own protected Keychain item. Your existing browser data and encryption key have not been changed.";
      return false;
    }
  }
  NSDictionary* saved = @{@"version": @1, @"service": identity.service, @"account": identity.account};
  NSError* error = nil;
  NSData* bytes = [NSJSONSerialization dataWithJSONObject:saved options:NSJSONWritingPrettyPrinted error:&error];
  if (!bytes || ![bytes writeToFile:marker options:NSDataWritingAtomic error:&error]) {
    *failure = @"Derivative couldn't save its Keychain configuration. Check that your browser profile is writable. Your existing browser data has not been reset.";
    return false;
  }
  return true;
}
}  // namespace DerivativeKeychain
