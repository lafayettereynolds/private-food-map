import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = (name: string) => readFileSync(new URL(name, import.meta.url), 'utf8')

describe('iOS QA companion app isolation contract', () => {
  it('keeps the private and QA apps independently installable', () => {
    const project = source('../../ios/TasteMap/TasteMap.xcodeproj/project.pbxproj')
    const scheme = source('../../ios/TasteMap/TasteMap.xcodeproj/xcshareddata/xcschemes/TasteMap QA.xcscheme')

    expect(project).toContain('PRODUCT_BUNDLE_IDENTIFIER = com.lafayette.tastemap;')
    expect(project).toContain('PRODUCT_BUNDLE_IDENTIFIER = com.lafayette.tastemap.qa;')
    expect(project).toContain('PRODUCT_BUNDLE_IDENTIFIER = com.lafayette.tastemap.qa.ShareExtension;')
    expect(project).toContain('INFOPLIST_KEY_CFBundleDisplayName = "味图测试";')
    expect(project).toContain('ASSETCATALOG_COMPILER_APPICON_NAME = AppIconQA;')
    expect(project).toContain('TASTEMAP_APP_GROUP_IDENTIFIER = group.com.lafayette.tastemap.qa;')
    expect(scheme).toContain('buildConfiguration = "DebugQA"')
    expect(existsSync(new URL('../../ios/TasteMap/TasteMap/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png', import.meta.url))).toBe(true)
    expect(existsSync(new URL('../../ios/TasteMap/TasteMap/Assets.xcassets/AppIconQA.appiconset/AppIconQA-1024.png', import.meta.url))).toBe(true)
  })

  it('does not let the QA Share Extension fall back to the private App Group', () => {
    const store = source('../../ios/TasteMap/TasteMapShared/PendingRestaurantImport.swift')
    const appEntitlements = source('../../ios/TasteMap/TasteMap/TasteMapQA.entitlements')
    const extensionEntitlements = source('../../ios/TasteMap/TasteMapShareExtension/TasteMapShareExtensionQA.entitlements')
    const extensionInfo = source('../../ios/TasteMap/TasteMapShareExtension/Info.plist')

    expect(store).toContain('#if TASTEMAP_QA')
    expect(store).toContain('fallbackAppGroupIdentifier = "group.com.lafayette.tastemap.qa"')
    expect(appEntitlements).toContain('<string>group.com.lafayette.tastemap.qa</string>')
    expect(extensionEntitlements).toContain('<string>group.com.lafayette.tastemap.qa</string>')
    expect(extensionInfo).toContain('<string>$(TASTEMAP_APP_GROUP_IDENTIFIER)</string>')
  })

  it('opens QA with isolated rich review data without changing private-app defaults', () => {
    const appRuntime = source('../../ios/TasteMap/TasteMap/App/TasteMapRuntimeConfiguration.swift')
    const hybridRuntime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntimeConfiguration.swift')
    const fixtures = source('../../ios/TasteMap/TasteMap/App/TasteMapUITestFixtures.swift')

    expect(appRuntime).toMatch(/#if TASTEMAP_QA\s+TasteMapRuntimeConfiguration\(tier: \.visualQA\)/)
    expect(hybridRuntime).toMatch(/#if DEBUG && \(TASTEMAP_QA \|\| TASTEMAP_PRIVATE_PREVIEW\)\s+return \.hybridDevelopment/)
    expect(fixtures).toMatch(/#if TASTEMAP_QA[\s\S]*?\?\? \.rich/)
  })

  it('keeps the physical private app on current Hybrid UI with real private storage', () => {
    const project = source('../../ios/TasteMap/TasteMap.xcodeproj/project.pbxproj')
    const scheme = source('../../ios/TasteMap/TasteMap.xcodeproj/xcshareddata/xcschemes/Taste Map Private.xcscheme')
    const hybridRuntime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntimeConfiguration.swift')
    const appRuntime = source('../../ios/TasteMap/TasteMap/App/TasteMapRuntimeConfiguration.swift')

    expect(scheme).toContain('buildConfiguration = "DebugPrivatePreview"')
    expect(project).toContain('SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG TASTEMAP_PRIVATE_PREVIEW $(inherited)";')
    expect(project).toMatch(/DebugPrivatePreview[\s\S]*?ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;[\s\S]*?PRODUCT_BUNDLE_IDENTIFIER = com\.lafayette\.tastemap;[\s\S]*?TASTEMAP_APP_GROUP_IDENTIFIER = group\.com\.lafayette\.tastemap;/)
    expect(hybridRuntime).toMatch(/#if DEBUG && \(TASTEMAP_QA \|\| TASTEMAP_PRIVATE_PREVIEW\)\s+return \.hybridDevelopment/)
    expect(appRuntime).not.toContain('TASTEMAP_PRIVATE_PREVIEW')
  })
})
