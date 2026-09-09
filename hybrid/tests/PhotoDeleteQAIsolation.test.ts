import { readFileSync } from 'node:fs'
import { expect, test } from 'vitest'

const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')

test('photo QA requires an isolated, network-denied opt-in runtime and normal session resolver', () => {
  const fixture = source('../../ios/TasteMap/TasteMap/App/PhotoDeleteQASessionFixture.swift')
  expect(fixture.trim().startsWith('#if DEBUG')).toBe(true)
  expect(fixture.trim().endsWith('#endif')).toBe(true)
  expect(fixture).toContain('runtime.isolatesPersistentState && !runtime.allowsNetwork')
  expect(fixture).toContain('TasteMapUITestFixtures.usesVisualQA')
  expect(fixture).toContain('environment[environmentKey] == "1"')
  expect(fixture).toContain('auth.restoreLocalAccountScope()')
  expect(fixture).toContain('AuthCredential(response:')
  expect(fixture).not.toContain('KeychainCredentialStore(')
  expect(fixture).not.toContain('URLSession.shared')
  expect(fixture).not.toContain('activateVisualQAFixture(')
  expect(fixture).not.toContain('currentUserID =')
  expect(fixture).toContain('guard photos[id] == owner')
})

test('formal release scan rejects QA route, identities and credential prefixes in the actual app', () => {
  const scan = source('../scripts/scan-formal-release-app.mjs')
  for (const marker of ['PhotoDeleteQASessionFixture', 'PhotoDeleteQASessionBootstrap',
    'TASTEMAP_PHOTO_DELETE_QA_SESSION', 'TASTEMAP_PHOTO_DELETE_QA_RUN',
    'photo-delete.qa.invalid', 'photo-qa-access-', 'photo-qa-refresh-',
    'qa-photo-owner', 'qa-photo-other-user']) expect(scan).toContain(`'${marker}'`)
  expect(scan).toContain('wholeAppText.includes(marker), false')
})
