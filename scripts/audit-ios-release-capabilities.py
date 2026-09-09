#!/usr/bin/env python3
"""Read-only local Release configuration/artifact audit; never installs or deploys.

This is not an Apple credential-lifecycle, App Privacy questionnaire, distribution
export, or real-device acceptance test. Those require separate evidence.
"""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path, help="Completed signed Release TasteMap.app")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
ios = root / "ios/TasteMap"
errors, checks = [], []


def check(value, label):
    checks.append({"check": label, "status": "PASS" if value else "FAIL"})
    if not value:
        errors.append(label)


def plist(path):
    return plistlib.loads(path.read_bytes())


def run(*command):
    return subprocess.check_output(command, stderr=subprocess.PIPE)


try:
    objects = json.loads(run("plutil", "-convert", "json", "-o", "-",
                             str(ios / "TasteMap.xcodeproj/project.pbxproj")))["objects"]
    targets = {t["name"]: t for t in objects.values() if t.get("isa") == "PBXNativeTarget"}
    check(set(targets) == {"TasteMap", "TasteMapShareExtension", "TasteMapTests", "TasteMapUITests"},
          "Formal target inventory")
    configs = {}
    for name, target in targets.items():
        configs[name] = {objects[c]["name"]: objects[c]["buildSettings"]
                         for c in objects[target["buildConfigurationList"]]["buildConfigurations"]}
    for name, suffix in [("TasteMap", ""), ("TasteMapShareExtension", ".ShareExtension")]:
        release = configs[name]["Release"]
        check(release["PRODUCT_BUNDLE_IDENTIFIER"] == "com.lafayette.tastemap" + suffix,
              name + " exact Release bundle identifier")
        check(release["DEVELOPMENT_TEAM"] == "7G5J9MJX88" and release["CODE_SIGN_STYLE"] == "Automatic",
              name + " Release signing settings")
        check(not release.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS"), name + " no target Release preview flags")
        for key in ["PRODUCT_BUNDLE_IDENTIFIER", "DEVELOPMENT_TEAM", "CODE_SIGN_STYLE", "PRODUCT_NAME",
                    "CURRENT_PROJECT_VERSION", "MARKETING_VERSION"]:
            check(release.get(key) == configs[name]["Debug"].get(key), name + " Debug/Release " + key)

    required = {"NSLocationWhenInUseUsageDescription", "NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"}
    main_info = plist(args.app / "Info.plist")
    check({k for k in main_info if k.endswith("UsageDescription")} == required,
          "Exactly foreground location, camera and add-only photo permission strings")
    check(not main_info.get("UIBackgroundModes"), "No background location/modes")
    release_permissions = {k: v for k, v in configs["TasteMap"]["Release"].items()
                           if k.endswith("UsageDescription")}
    for name, settings in configs["TasteMap"].items():
        check({k: v for k, v in settings.items() if k.endswith("UsageDescription")} == release_permissions,
              name + " permission configuration parity")
    for key, value in release_permissions.items():
        check(main_info.get(key.removeprefix("INFOPLIST_KEY_")) == value, key + " built value")

    app_ent = plist(ios / "TasteMap/TasteMapRelease.entitlements")
    ext_ent = plist(ios / "TasteMapShareExtension/TasteMapShareExtension.entitlements")
    check(app_ent.get("com.apple.developer.applesignin") == ["Default"], "Main Apple Sign In")
    check(app_ent.get("com.apple.developer.associated-domains") == ["applinks:tastemap.cn"], "Production domain only")
    check(set(ext_ent) == {"com.apple.security.application-groups"}, "Extension minimal entitlements")
    for label, bundle, source, manifest in [
        ("Main", args.app, app_ent, ios / "TasteMap/PrivacyInfo.xcprivacy"),
        ("Share", args.app / "PlugIns/TasteMapShareExtension.appex", ext_ent,
         ios / "TasteMapShareExtension/PrivacyInfo.xcprivacy"),
    ]:
        actual = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(bundle)))
        run("codesign", "--verify", "--deep", "--strict", str(bundle))
        check(all(actual.get(k) == v for k, v in source.items()), label + " signed/source entitlement parity")
        check(actual.get("com.apple.security.application-groups") == ["group.com.lafayette.tastemap"], label + " shared queue group")
        check(not actual.get("keychain-access-groups"), label + " no cross-target Keychain Sharing")
        check((bundle / "PrivacyInfo.xcprivacy").read_bytes() == manifest.read_bytes(), label + " privacy manifest byte parity")
    ext_info = plist(args.app / "PlugIns/TasteMapShareExtension.appex/Info.plist")
    check(not any(k.endswith("UsageDescription") for k in ext_info), "Extension no app-only privacy permissions")
    extension = ext_info.get("NSExtension", {})
    check(extension.get("NSExtensionPointIdentifier") == "com.apple.share-services", "Share extension point")
    check(extension.get("NSExtensionAttributes", {}).get("NSExtensionActivationRule") == {
        "NSExtensionActivationSupportsText": True, "NSExtensionActivationSupportsWebURLWithMaxCount": 1},
        "Share supports text and one URL, no TRUEPREDICATE")
    check(main_info.get("CFBundleVersion") == ext_info.get("CFBundleVersion"), "Embedded build version equality")
except Exception as error:
    errors.append(str(error))

print(json.dumps({"scope": "local Release config and completed signed artifact only",
                  "status": "FAIL" if errors else "PASS", "checks": checks, "errors": errors}, indent=2))
raise SystemExit(bool(errors))
