#!/usr/bin/env python3
"""Source declaration tests; never certify a deployed page or signed archive."""
import copy
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('privacy_audit', ROOT / 'scripts/audit-ios-privacy.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
MAIN = ROOT / 'ios/TasteMap/TasteMap/PrivacyInfo.xcprivacy'

class PrivacySubmission(unittest.TestCase):
    def test_reviewed_main(self):
        self.assertEqual(len(audit.validate_manifest(MAIN, main=True)['NSPrivacyCollectedDataTypes']), 13)

    def test_extension_not_mechanically_expanded(self):
        audit.validate_manifest(ROOT / 'ios/TasteMap/TasteMapShareExtension/PrivacyInfo.xcprivacy')

    def test_inaccurate_declarations_rejected(self):
        original = audit.read_plist(MAIN)
        for change in ['missing_search', 'tracking', 'purchase_personalization', 'unlinked', 'extra_crash', 'wrong_reason']:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                value = copy.deepcopy(original)
                data = value['NSPrivacyCollectedDataTypes']
                if change == 'missing_search':
                    value['NSPrivacyCollectedDataTypes'] = [x for x in data if not x['NSPrivacyCollectedDataType'].endswith('SearchHistory')]
                elif change == 'tracking':
                    value['NSPrivacyTracking'] = True
                elif change == 'purchase_personalization':
                    next(x for x in data if x['NSPrivacyCollectedDataType'].endswith('PurchaseHistory'))['NSPrivacyCollectedDataTypePurposes'].append('NSPrivacyCollectedDataTypePurposeProductPersonalization')
                elif change == 'unlinked':
                    data[0]['NSPrivacyCollectedDataTypeLinked'] = False
                elif change == 'extra_crash':
                    extra = copy.deepcopy(data[0])
                    extra['NSPrivacyCollectedDataType'] = 'NSPrivacyCollectedDataTypeCrashData'
                    data.append(extra)
                else:
                    value['NSPrivacyAccessedAPITypes'][0]['NSPrivacyAccessedAPITypeReasons'] = ['INVALID']
                path = Path(directory) / 'PrivacyInfo.xcprivacy'
                with path.open('wb') as stream:
                    plistlib.dump(value, stream)
                with self.assertRaises(ValueError):
                    audit.validate_manifest(path, main=True)

    def test_canonical_pages(self):
        for page in ['privacy.html', 'support.html']:
            with self.subTest(page=page):
                source = (ROOT / 'web-public/public' / page).read_text()
                self.assertNotRegex(source, r'(?i)TODO|placeholder|待填写|待确认|待核对|上线前|<!--')
                for text in ['418378071@qq.com', '浙ICP备2026070007号-1A', '账户与安全', '删除账户', 'name="viewport"']:
                    self.assertIn(text, source)
        source = (ROOT / 'web-public/public/privacy.html').read_text()
        for text in ['30 天', '90 天', '365 天', '已关闭账户的举报记录', '正式服务已启用', '查询参数', 'Open-Meteo', 'Photon', 'QQ 邮箱', 'StoreKit']:
            self.assertIn(text, source)

    def test_no_new_permissions(self):
        source = (ROOT / 'ios/TasteMap/TasteMap.xcodeproj/project.pbxproj').read_text()
        for key in ['NSContactsUsageDescription', 'NSMicrophoneUsageDescription', 'NSBluetoothAlwaysUsageDescription', 'NSLocationAlwaysUsageDescription', 'NSLocationAlwaysAndWhenInUseUsageDescription']:
            self.assertNotIn(key, source)
        for key in ['NSLocationWhenInUseUsageDescription', 'NSCameraUsageDescription', 'NSPhotoLibraryAddUsageDescription']:
            self.assertIn(key, source)

if __name__ == '__main__':
    unittest.main()
