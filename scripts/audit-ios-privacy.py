#!/usr/bin/env python3
"""Validate the actual formal Release archive; source-only checks are insufficient.

Usage: python3 scripts/audit-ios-privacy.py path/to/TasteMap.xcarchive
This verifies the reviewed inventory, not arbitrary future API/data-flow compliance.
Re-audit the inventory when dependencies or data collection change.
"""
import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API_REASONS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
}
DATA_TYPES = {
    "Name", "EmailAddress", "UserID", "PurchaseHistory", "PhotosorVideos",
    "OtherUserContent", "PreciseLocation", "CoarseLocation", "Contacts", "ProductInteraction",
}
TOP_KEYS = {
    "NSPrivacyTracking", "NSPrivacyTrackingDomains",
    "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_plist(path):
    require(path.is_file(), f"Missing real file: {path}")
    with path.open("rb") as stream:
        return plistlib.load(stream)


def validate_manifest(path, main=False):
    value = read_plist(path)
    require(set(value) == TOP_KEYS, f"Unexpected/missing root keys: {path}")
    require(value["NSPrivacyTracking"] is False, f"Unexpected tracking: {path}")
    require(value["NSPrivacyTrackingDomains"] == [], f"Unexpected tracking domains: {path}")
    accessed = value["NSPrivacyAccessedAPITypes"]
    require(isinstance(accessed, list), f"API categories must be an array: {path}")
    reasons = {}
    for item in accessed:
        require(set(item) == {"NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"},
                f"Invalid API entry: {path}")
        category = item["NSPrivacyAccessedAPIType"]
        require(category not in reasons, f"Duplicate API category: {path}")
        reasons[category] = item["NSPrivacyAccessedAPITypeReasons"]
    require(reasons == (API_REASONS if main else {}), f"Unreviewed API declaration: {path}")
    collected = value["NSPrivacyCollectedDataTypes"]
    require(isinstance(collected, list), f"Collection must be an array: {path}")
    types = []
    for item in collected:
        require(set(item) == {"NSPrivacyCollectedDataType", "NSPrivacyCollectedDataTypeLinked",
                "NSPrivacyCollectedDataTypeTracking", "NSPrivacyCollectedDataTypePurposes"},
                f"Invalid collection entry: {path}")
        name = item["NSPrivacyCollectedDataType"]
        types.append(name)
        require(item["NSPrivacyCollectedDataTypeLinked"] is True, f"Incorrect linkage: {path}")
        require(item["NSPrivacyCollectedDataTypeTracking"] is False, f"Incorrect tracking: {path}")
        purposes = ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
        if name not in {"NSPrivacyCollectedDataType" + t for t in ["Name", "EmailAddress", "PhotosorVideos"]}:
            purposes.append("NSPrivacyCollectedDataTypePurposeProductPersonalization")
        require(item["NSPrivacyCollectedDataTypePurposes"] == purposes, f"Incorrect purpose: {path}: {name}")
    expected = {"NSPrivacyCollectedDataType" + t for t in DATA_TYPES} if main else set()
    require(set(types) == expected and len(types) == len(set(types)), f"Missing/duplicate/unreviewed data: {path}")
    return value


def main():
    require(len(sys.argv) == 2, "Supply the actual Release .xcarchive path")
    archive = Path(sys.argv[1]).resolve()
    info = read_plist(archive / "Info.plist")
    require(info.get("SchemeName") == "TasteMap", "Not the formal TasteMap scheme archive")
    app = archive / "Products/Applications/TasteMap.app"
    require(read_plist(app / "Info.plist")["CFBundleIdentifier"] == "com.lafayette.tastemap",
            "Wrong app identity (QA/internal shell is not Release evidence)")
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-",
        str(ROOT / "ios/TasteMap/TasteMap.xcodeproj/project.pbxproj"),
    ]))
    objects = project["objects"]
    for target_name, folder in [("TasteMap", "TasteMap"), ("TasteMapShareExtension", "TasteMapShareExtension")]:
        target = next(v for v in objects.values() if v.get("isa") == "PBXNativeTarget" and v.get("name") == target_name)
        groups = [objects[g] for g in target.get("fileSystemSynchronizedGroups", [])]
        group = next(g for g in groups if g.get("path") == folder)
        for exception_id in group.get("exceptions", []):
            require("PrivacyInfo.xcprivacy" not in objects[exception_id].get("membershipExceptions", []),
                    f"Manifest excluded from {target_name}")
    expected_paths = {
        "PrivacyInfo.xcprivacy": ROOT / "ios/TasteMap/TasteMap/PrivacyInfo.xcprivacy",
        "PlugIns/TasteMapShareExtension.appex/PrivacyInfo.xcprivacy": ROOT / "ios/TasteMap/TasteMapShareExtension/PrivacyInfo.xcprivacy",
        "Frameworks/Capacitor.framework/PrivacyInfo.xcprivacy": None,
        "Frameworks/Cordova.framework/PrivacyInfo.xcprivacy": None,
    }
    found = {p.relative_to(app).as_posix() for p in app.rglob("PrivacyInfo.xcprivacy")}
    require(found == set(expected_paths), f"Missing/extra/duplicate bundled manifests: {found ^ set(expected_paths)}")
    frameworks = {p.name for p in (app / "Frameworks").glob("*.framework")}
    require(frameworks == {"Capacitor.framework", "Cordova.framework"}, f"Unreviewed SDK inventory: {frameworks}")
    result = {"archive": str(archive), "app": str(app), "manifests": []}
    for relative, source in expected_paths.items():
        path = app / relative
        value = validate_manifest(path, main=relative == "PrivacyInfo.xcprivacy")
        if source:
            require(value == read_plist(source), f"Stale archived manifest: {relative}")
        result["manifests"].append({"path": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "content": value})
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result["status"] = "PASS"
    output = archive.parent / "archive-privacy-verification.json"
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"PASS: formal target membership, app identity, four actual manifests, exact reviewed declarations, source/artifact equality and archive code signatures.\nEvidence: {output}")


if __name__ == "__main__":
    main()
