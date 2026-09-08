import type { AnalysisShareData } from '../types/analysisShare'
import { filterAnalysisSharePrivacy } from './analysisShare'
import { resolveVisualForPoster } from './foodVisualResolver'
import { posterFoodArtwork, posterObjectArtwork, posterPreferenceArtwork, type PosterObjectArtwork } from './posterFoodArtwork'
import { posterIcon, posterTasteIcon } from './posterDrawing'
import { renderEditorialPoster, EDITORIAL_POSTER_HEIGHT } from './analysisEditorialRenderer'

export const POSTER_WIDTH = 1080
export const POSTER_HEIGHT = 1920
export const TASTE_PROFILE_POSTER_HEIGHT = 1620

export interface PreparedAnalysisPoster {
  data: AnalysisShareData
  hero: string | null
  logo: string | null
  restaurantImages: Array<string | null>
  heroIndex: number
  heroIsIllustration?: boolean
  restaurantIllustrations?: boolean[]
  cuisineArtwork?: Array<string | null>
  preferenceArtwork?: Array<string | null>
  objectArtwork?: Partial<Record<PosterObjectArtwork, string | null>>
  editorialArtwork?: Record<string, string | null>
}

const escapeXml = (value: string) => value.replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[character] || character))
type GraphemeSegmenter = new (locale: string, options: { granularity: 'grapheme' }) => { segment(value: string): Iterable<{ segment: string }> }
const segmenter = (Intl as typeof Intl & { Segmenter?: GraphemeSegmenter }).Segmenter
const graphemes = (value: string) => segmenter
  ? [...new segmenter('zh-CN', { granularity: 'grapheme' }).segment(value)].map(item => item.segment)
  : Array.from(value) // older engines preserve code points, never split surrogate pairs
const cut = (value: string, length: number) => graphemes(value).length > length ? `${graphemes(value).slice(0, length - 1).join('')}…` : value

export async function prepareAnalysisPoster(data: AnalysisShareData, heroIndex = 0): Promise<PreparedAnalysisPoster> {
  const safeData = filterAnalysisSharePrivacy(data, {
    includeCompanionName: data.privacy.companionNameIncluded,
    includeSpend: data.privacy.spendIncluded,
  })
  const index = safeData.heroCandidates.length ? ((heroIndex % safeData.heroCandidates.length) + safeData.heroCandidates.length) % safeData.heroCandidates.length : 0
  const [actualHero, logo, restaurantVisuals, cuisineArtwork, preferenceArtwork, objects, editorialArtwork] = await Promise.all([
    resolveVisualForPoster(safeData.heroCandidates[index]),
    resolveVisualForPoster({ source: safeData.logoSource, photoId: null, origin: 'restaurant', label: 'Taste Map' }),
    Promise.all(safeData.restaurants.slice(0, 3).map(async (restaurant) => {
      const actual = await resolveVisualForPoster(restaurant.image)
      return { image: actual ?? await posterFoodArtwork(restaurant.name, restaurant.image.tags), illustration: !actual || restaurant.image.origin === 'fallback' }
    })),
    Promise.all((safeData.tasteProfile?.cuisines ?? []).slice(0, 7).map(item => posterFoodArtwork(item.label))),
    Promise.all((safeData.tasteProfile?.preferences ?? []).slice(0, 6).map(item => posterPreferenceArtwork(item.label))),
    safeData.tasteProfile ? Promise.all((['restaurant', 'dish', 'city'] as const).map(async key => [key, await posterObjectArtwork(key)] as const)) : [],
    Promise.all((safeData.editorial ? [{ id: 'cuisines', rows: safeData.editorial.cuisines }, ...safeData.editorial.sections] : []).flatMap(section => section.rows.map(async (row, index) => [ `${section.id}:${index}`, row.visual ? await resolveVisualForPoster(row.visual) ?? await posterFoodArtwork(row.visual.label, row.visual.tags) : null ] as const))),
  ])
  const reference = safeData.heroCandidates[index] ?? safeData.restaurants[0]?.image
  const hero = actualHero ?? await posterFoodArtwork(reference?.label ?? '美食', reference?.tags)
  return { data: safeData, hero, logo, restaurantImages: restaurantVisuals.map(item => item.image), restaurantIllustrations: restaurantVisuals.map(item => item.illustration), heroIndex: index, heroIsIllustration: !actualHero || reference?.origin === 'fallback', cuisineArtwork, preferenceArtwork, objectArtwork: Object.fromEntries(objects), editorialArtwork: Object.fromEntries(editorialArtwork) }
}

/** Width-aware CJK/Latin wrapping, without cutting the middle of a fact. */
export function posterTextLines(text: string, width: number, fontSize: number) {
  const lines: string[] = []; let line = ''; let used = 0
  for (const character of graphemes(text)) {
    const units = /[\u0000-\u007f]/.test(character) ? .57 : 1
    if (character === '\n' || (line && used + units > width / fontSize)) {
      lines.push(line); line = ''; used = 0
      if (character === '\n') continue
    }
    line += character; used += units
  }
  if (line) lines.push(line)
  return lines
}

/** Explicit ellipsis when a fixed poster excerpt cannot fit; no silent fact tail. */
function excerptLines(text: string, width: number, fontSize: number, maximum: number) {
  const lines = posterTextLines(text, width, fontSize)
  if (lines.length <= maximum) return lines
  const visible = lines.slice(0, maximum)
  visible[maximum - 1] = `${graphemes(visible[maximum - 1]).slice(0, -1).join('')}…`
  return visible
}

/** Editorial headings vary with the report's purpose, not with its calculator. */
const posterNarrative: Record<AnalysisShareData['type'], { findings: string; evidence: string; scope: string }> = {
  TASTE_PROFILE: { findings: '口味发现', evidence: '最常吃 TOP 3', scope: '习惯与偏好' },
  COMPANION_ANALYSIS: { findings: '共同餐桌上的发现', evidence: '一起吃过的餐厅', scope: '基于你的同行记录' },
  RECOMMENDATION_SOURCE: { findings: '验证后的发现', evidence: '实际体验的餐厅', scope: '仅代表你的体验' },
  MONTHLY_REVIEW: { findings: '这个月值得记住', evidence: '本月餐厅记忆', scope: '本期真实用餐记录' },
  ANNUAL_REVIEW: { findings: '这一年的食味线索', evidence: '年度餐厅记忆', scope: '年度食味年鉴' },
  ON_THIS_DAY: { findings: '那天的味觉记忆', evidence: '记忆中的餐厅', scope: '真实记录里的那一天' },
}

function posterFindings(data: AnalysisShareData) {
  // Legacy payloads retain their original insights. A present empty list is an
  // explicit insufficient state and must never fall back to unsupported prose.
  return data.posterFindings?.map(item => `${item.title} · ${item.text}`)
    ?? [...new Set(data.insights)].filter(value => value && value !== data.summary)
}

export function renderAnalysisPosterSvg(prepared: PreparedAnalysisPoster) {
  const { data, hero, logo, restaurantImages } = prepared
  if (data.editorial) return renderEditorialPoster(prepared)
  if (data.memoryCard) return renderMemoryCard(prepared)
  if (data.type === 'RECOMMENDATION_SOURCE' && data.sourceResults) return renderSourceResultsPoster(prepared)
  if (data.type === 'TASTE_PROFILE' && data.tasteProfile) {
    return renderTasteProfilePosterSvg(prepared)
  }
  const themes: Record<AnalysisShareData['type'], { accent: string; soft: string; symbol: string }> = {
    TASTE_PROFILE: { accent: '#D56749', soft: '#F7E6D6', symbol: '口味画像' },
    COMPANION_ANALYSIS: { accent: '#A96656', soft: '#F3E1DA', symbol: '一起吃饭' },
    RECOMMENDATION_SOURCE: { accent: '#B0793E', soft: '#F4E8D0', symbol: '推荐验证' },
    MONTHLY_REVIEW: { accent: '#647F78', soft: '#E2ECE7', symbol: '月度回味' },
    ANNUAL_REVIEW: { accent: '#506C8C', soft: '#E2E9F0', symbol: '年度轨迹' },
    ON_THIS_DAY: { accent: '#876D8E', soft: '#EDE4EF', symbol: '味觉记忆' },
  }
  const theme = themes[data.type]
  const narrative = posterNarrative[data.type]
  const parts: string[] = [`<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920">`]
  parts.push(`<defs><clipPath id="heroCircle"><circle cx="540" cy="665" r="224"/></clipPath><filter id="softShadow"><feDropShadow dx="0" dy="18" stdDeviation="24" flood-color="#6E5D4C" flood-opacity=".18"/></filter><linearGradient id="heroFallback" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${theme.soft}"/><stop offset="1" stop-color="#FFFFFF"/></linearGradient></defs>`)
  parts.push(`<rect width="1080" height="1920" fill="#FBFAF6"/>`)
  parts.push(`<circle cx="1000" cy="100" r="190" fill="${theme.soft}" opacity=".42"/><circle cx="52" cy="1030" r="140" fill="${theme.soft}" opacity=".30"/>`)
  parts.push(`<rect x="56" y="52" width="246" height="66" rx="33" fill="#FFFFFF" stroke="#E5E0D9"/>`)
  if (logo) parts.push(`<image href="${logo}" x="68" y="61" width="48" height="48"/>`)
  parts.push(`<text x="128" y="94" font-family="system-ui,sans-serif" font-size="27" font-weight="720" fill="#2E3A42">Taste Map</text>`)
  parts.push(`<text x="58" y="176" font-family="system-ui,sans-serif" font-size="21" letter-spacing="5" fill="#8A7B6F">${escapeXml(data.eyebrow)}</text>`)
  parts.push(`<text x="56" y="246" font-family="system-ui,sans-serif" font-size="64" font-weight="780" fill="#22282C">${escapeXml(cut(data.title, 18))}</text>`)
  parts.push(`<text x="58" y="292" font-family="system-ui,sans-serif" font-size="24" fill="#7F7770">${escapeXml(cut(data.subtitle, 38))}</text>`)
  parts.push(`<rect x="56" y="330" width="968" height="104" rx="22" fill="#FFFFFF" stroke="#E8E2DA"/>`)
  parts.push(`<text x="82" y="357" font-family="system-ui,sans-serif" font-size="18" font-weight="720" fill="${theme.accent}">${theme.symbol}</text>`)
  excerptLines(data.summary.trim(), 900, 24, 2).forEach((line, index) =>
    parts.push(`<text x="82" y="${390 + index * 30}" font-family="system-ui,sans-serif" font-size="24" font-weight="620" fill="#33434D">${escapeXml(line)}</text>`))
  const nodePositions = [[165, 540], [890, 535], [105, 735], [975, 738], [225, 930], [835, 938]]
  nodePositions.slice(0, Math.min(data.metrics.length + data.keywords.length, 6)).forEach(([x, y], index) => {
    const metric = data.metrics[index]
    const keyword = data.keywords[index - data.metrics.length]
    const label = metric?.label ?? keyword ?? '真实记录'
    const value = metric?.value ?? (keyword ? '偏好' : '—')
    parts.push(`<line x1="540" y1="665" x2="${x}" y2="${y}" stroke="#CFC8BE" stroke-width="2" stroke-dasharray="8 10"/>`)
    parts.push(`<circle cx="${x}" cy="${y}" r="76" fill="#FFFFFF" stroke="${theme.soft}" stroke-width="8"/>`)
    parts.push(`<text x="${x}" y="${y - 3}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="25" font-weight="760" fill="${theme.accent}">${escapeXml(cut(value, 9))}</text>`)
    parts.push(`<text x="${x}" y="${y + 29}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#746C66">${escapeXml(cut(label, 8))}</text>`)
  })
  parts.push(`<circle cx="540" cy="665" r="238" fill="#FFFFFF" stroke="#EEE5DB" stroke-width="2" filter="url(#softShadow)"/>`)
  if (hero) parts.push(`<image href="${hero}" x="316" y="441" width="448" height="448" preserveAspectRatio="xMidYMid slice" clip-path="url(#heroCircle)"/>`)
  else parts.push(`<circle cx="540" cy="665" r="224" fill="url(#heroFallback)"/><text x="540" y="654" text-anchor="middle" font-family="system-ui,sans-serif" font-size="84">◯</text><text x="540" y="708" text-anchor="middle" font-family="system-ui,sans-serif" font-size="24" fill="#7B6E64">真实餐饮记录</text>`)
  if (prepared.heroIsIllustration) parts.push(`<text x="540" y="916" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#7B6E64">食物素材插画 · 非餐厅实拍</text>`)
  parts.push(`<rect x="56" y="1050" width="626" height="292" rx="26" fill="#FFFFFF" stroke="#E8E2DA"/>`)
  parts.push(`<text x="84" y="1101" font-family="system-ui,sans-serif" font-size="28" font-weight="740" fill="#2C353B">${narrative.findings}</text>`)
  let insightY = 1146
  let shownInsights = 0
  for (const insight of posterFindings(data)) {
    const lines = posterTextLines(insight, 530, 22)
    if (insightY + lines.length * 29 > 1322) continue
    parts.push(`<circle cx="94" cy="${insightY - 7}" r="6" fill="${theme.accent}"/>`)
    for (const line of lines) { parts.push(`<text x="118" y="${insightY}" font-family="system-ui,sans-serif" font-size="22" fill="#40515B">${escapeXml(line)}</text>`); insightY += 29 }
    insightY += 12
    shownInsights += 1
    if (shownInsights === 3) break
  }
  if (!shownInsights) parts.push(`<text x="84" y="1150" font-family="system-ui,sans-serif" font-size="20" fill="#746C66">${data.posterFindings?.length === 0 ? '记录仍在积累，先珍藏真实经历。' : '完整发现保留在数据报告中。'}</text>`)
  parts.push(`<rect x="704" y="1050" width="320" height="292" rx="26" fill="${theme.soft}" fill-opacity=".68" stroke="#E5DDD3"/>`)
  parts.push(`<text x="730" y="1101" font-family="system-ui,sans-serif" font-size="24" font-weight="740" fill="#2C353B">${narrative.scope}</text>`)
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    parts.push(`<circle cx="750" cy="${1151 + index * 58}" r="18" fill="${theme.accent}"/><text x="750" y="${1159 + index * 58}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="17" font-weight="750" fill="#FFFFFF">${index + 1}</text><text x="782" y="${1158 + index * 58}" font-family="system-ui,sans-serif" font-size="21" font-weight="650" fill="#3E464B">${escapeXml(cut(restaurant.name, 10))}</text>`)
  })
  if (data.restaurants.length) parts.push(`<text x="56" y="1402" font-family="system-ui,sans-serif" font-size="29" font-weight="740" fill="#2C353B">${narrative.evidence}</text>`)
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    const x = 56 + index * 328
    parts.push(`<rect x="${x}" y="1432" width="304" height="326" rx="24" fill="#FFFFFF" stroke="#E8E2DA"/>`)
    if (restaurantImages[index]) parts.push(`<image href="${restaurantImages[index]}" x="${x}" y="1432" width="304" height="204" preserveAspectRatio="xMidYMid slice" clip-path="inset(0 round 24px 24px 0 0)"/>`)
    else parts.push(`<rect x="${x}" y="1432" width="304" height="204" rx="24" fill="${theme.soft}"/><text x="${x + 152}" y="1546" text-anchor="middle" font-family="system-ui,sans-serif" font-size="20" fill="#796F67">暂无真实图片</text>`)
    parts.push(`<text x="${x + 18}" y="1681" font-family="system-ui,sans-serif" font-size="22" font-weight="720" fill="#2C353B">${escapeXml(cut(restaurant.name, 12))}</text>`)
    parts.push(`<text x="${x + 18}" y="1718" font-family="system-ui,sans-serif" font-size="17" fill="#7B7772">${escapeXml(cut(restaurant.meta, 20))}</text>`)
    if (restaurant.score) parts.push(`<text x="${x + 286}" y="1745" text-anchor="end" font-family="system-ui,sans-serif" font-size="18" font-weight="700" fill="${theme.accent}">${escapeXml(restaurant.score)} / 10</text>`)
    if (prepared.restaurantIllustrations?.[index]) parts.push(`<text x="${x + 18}" y="1745" font-family="system-ui,sans-serif" font-size="14" fill="#7B7772">素材插画 · 非实拍</text>`)
  })
  parts.push(`<line x1="56" y1="1832" x2="1024" y2="1832" stroke="#DED8D0"/>`)
  parts.push(`<text x="56" y="1877" font-family="system-ui,sans-serif" font-size="19" fill="#7B7772">${escapeXml(data.footer)}</text>`)
  parts.push(`<text x="1024" y="1877" text-anchor="end" font-family="system-ui,sans-serif" font-size="18" fill="${theme.accent}">基于真实记录生成</text>`)
  parts.push('</svg>')
  return parts.join('')
}

function renderMemoryCard({ data, hero, logo, heroIsIllustration }: PreparedAnalysisPoster) {
  const text = (x: number, y: number, value: string, size = 30, color = '#1c3445', weight = 500) => `<text x="${x}" y="${y}" font-family="system-ui,sans-serif" font-size="${size}" font-weight="${weight}" fill="${color}">${escapeXml(value)}</text>`
  const parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><rect width="1080" height="1920" fill="#fdfcf9"/>']
  parts.push(text(76, 104, data.eyebrow, 24, '#6d818c'), text(76, 196, data.title, 62, '#1c3445', 750))
  excerptLines(data.subtitle, 920, 28, 2).forEach((line, index) => parts.push(text(76, 254 + index * 38, line, 28, '#6d818c')))
  excerptLines(data.summary, 920, 45, 4).forEach((line, index) => parts.push(text(76, 374 + index * 65, line, 45, '#1c3445', 700)))
  parts.push('<g transform="rotate(-3 540 885)"><rect x="130" y="640" width="820" height="600" fill="#fff" stroke="#e4e3dd" stroke-width="3"/>')
  if (hero) parts.push(`<image href="${hero}" x="157" y="667" width="766" height="490" preserveAspectRatio="xMidYMid meet"/>`)
  parts.push(text(175, 1200, heroIsIllustration ? '食物插画 · 非餐厅实拍' : '这一顿，记住了。', 24, '#879088'), '</g>')
  const metrics = data.metrics.slice(0, 4); const width = 928 / Math.max(metrics.length, 1)
  parts.push('<path d="M76 1340H1004 M76 1498H1004" stroke="#dce5e8" stroke-width="2"/>')
  metrics.forEach((metric, index) => { const x = 76 + index * width; parts.push(text(x + 8, 1407, cut(metric.value, 10), 39, '#1c3445', 700), text(x + 8, 1460, cut(metric.label, 12), 22, '#6d818c')); if (index) parts.push(`<path d="M${x - 8} 1364V1475" stroke="#dce5e8"/>`) })
  excerptLines('把真实的一餐，留给未来的自己。', 920, 31, 2).forEach((line, index) => parts.push(text(76, 1620 + index * 42, line, 31, '#4c7192')))
  if (logo) parts.push(`<image href="${logo}" x="76" y="1775" width="64" height="64"/>`)
  parts.push(text(158, 1817, 'Taste Map', 30, '#1c3445', 700))
  excerptLines(data.footer, 920, 20, 2).forEach((line, index) => parts.push(text(76, 1865 + index * 26, line, 20, '#6d818c')))
  parts.push('</svg>'); return parts.join('')
}

function renderSourceResultsPoster({ data, hero, logo, restaurantImages, heroIsIllustration, restaurantIllustrations }: PreparedAnalysisPoster) {
  const result = data.sourceResults!
  const text = (x: number, y: number, value: string, size = 26, color = '#344650', weight = 500) => `<text x="${x}" y="${y}" font-family="system-ui,sans-serif" font-size="${size}" font-weight="${weight}" fill="${color}">${escapeXml(value)}</text>`
  const box = (x: number, y: number, w: number, h: number, fill = '#ffffff') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="20" fill="${fill}" stroke="#e3dbd0"/>`
  const parts = [`<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920" viewBox="0 0 1080 1920"><rect width="1080" height="1920" fill="#fbfaf6"/><defs><clipPath id="sourceHero"><circle cx="540" cy="535" r="180"/></clipPath></defs>`]
  parts.push(text(64, 88, 'RECOMMENDATION SOURCES', 22, '#877365'), text(64, 176, '谁最会种草', 62, '#24343d', 750), text(64, 228, cut(data.periodLabel ?? data.subtitle, 36), 24))
  excerptLines(data.summary, 940, 28, 2).forEach((line, index) => parts.push(text(64, 280 + index * 34, line, 28, '#8b613f', 600)))
  parts.push(`<circle cx="540" cy="535" r="188" fill="#f0e5d6" stroke="#dfcfba"/>`)
  if (hero) parts.push(`<image href="${hero}" x="360" y="355" width="360" height="360" preserveAspectRatio="xMidYMid slice" clip-path="url(#sourceHero)"/>`)
  else parts.push(text(433, 542, '真实体验记录', 32))
  if (heroIsIllustration) parts.push(text(383, 736, '食物素材插画 · 非餐厅实拍', 20, '#7a726b'))
  for (const [index, label] of ['关联餐厅', '实际到访', '首次评分'].entries()) {
    const x = 100 + index * 320
    parts.push(box(x, 752, 240, 68, '#f5eee3'), text(x + 60, 796, label, 27))
    if (index < 2) parts.push(text(x + 262, 796, '→', 28))
  }
  parts.push(text(64, 851, '全部来源比较 · 并非当前所选来源的单独成绩', 20, '#7a726b'))
  for (const [index, entry] of [result.best, result.worst].entries()) {
    const x = 64 + index * 490, color = index ? '#a85b49' : '#52776a'
    parts.push(box(x, 865, 462, 366, index ? '#fff5ef' : '#f3f7f1'), text(x + 26, 917, index ? '最坑推荐来源' : '最会种草', 30, color, 700))
    if (!entry) { parts.push(text(x + 26, 993, '暂无符合条件的来源', 25), text(x + 26, 1042, '有记录才下结论，不补空缺', 23)); continue }
    parts.push(text(x + 26, 973, cut(entry.name, 14), 28, '#344650', 650), text(x + 26, 1044, `${index ? '踩坑率' : '高分占比'} ${Math.round(entry.rate * 100)}%`, 42, color, 750), text(x + 26, 1100, `验证 ${entry.count} 家 · ${entry.outcomeCount} 家${index ? '踩坑' : '高分'}`, 24), text(x + 26, 1150, `首次体验均分 ${entry.average.toFixed(1)} / 10`, 24))
  }
  parts.push(text(64, 1290, `你的整体首次体验均分 ${result.baseline == null ? '未评分' : `${result.baseline.toFixed(1)} / 10`} · ${result.baselineCount} 家`, 26), text(64, 1336, '踩坑：首次体验比上述未取整均分低至少 1 分', 24, '#7a726b'))
  parts.push(text(64, 1410, '当前所选来源 · 代表餐厅', 32, '#344650', 700))
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    const y = 1440 + index * 108
    if (restaurantImages[index]) parts.push(`<image href="${restaurantImages[index]}" x="64" y="${y}" width="88" height="88" preserveAspectRatio="xMidYMid slice"/>`)
    parts.push(text(174, y + 34, cut(restaurant.name, 26), 26, '#344650', 650), text(174, y + 73, cut(restaurant.meta, 30), 23, '#7a726b'))
    if (restaurantIllustrations?.[index]) parts.push(text(64, y + 103, '素材插画', 12, '#7a726b'))
  })
  parts.push(text(64, 1800, '仅基于个人记录 · 未到访、未评分不算失败 · 多来源未明确主来源不排名', 20, '#7a726b'), `<path d="M64 1832H1016" stroke="#ded6ca"/>`)
  if (logo) parts.push(`<image href="${logo}" x="64" y="1852" width="40" height="40"/>`)
  parts.push(text(118, 1880, 'Taste Map · 真实记录', 24), text(548, 1880, data.privacy.spendIncluded ? '本人预览 · 分享前请查看脱敏版本' : '消费、私人备注与同行姓名默认隐藏', 20, '#7a726b'), '</svg>')
  return parts.join('')
}

function renderTasteProfilePosterSvg(prepared: PreparedAnalysisPoster) {
  const { data, hero, logo, restaurantImages } = prepared
  const taste = data.tasteProfile!
  const parts: string[] = [`<svg xmlns="http://www.w3.org/2000/svg" width="${POSTER_WIDTH}" height="${TASTE_PROFILE_POSTER_HEIGHT}" viewBox="0 0 ${POSTER_WIDTH} ${TASTE_PROFILE_POSTER_HEIGHT}">`]
  parts.push(`<defs>
    <filter id="tpShadow"><feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#6B5A48" flood-opacity=".13"/></filter>
    <filter id="tpSoft"><feDropShadow dx="0" dy="5" stdDeviation="8" flood-color="#6B5A48" flood-opacity=".09"/></filter>
    <clipPath id="tpHero"><circle cx="505" cy="430" r="164"/></clipPath>
    ${restaurantImages.slice(0, 3).map((_, index) => `<clipPath id="tpRestaurant${index}"><circle cx="${112}" cy="${795 + index * 82}" r="31"/></clipPath>`).join('')}
  </defs>`)
  parts.push(`<rect width="1080" height="1620" rx="18" fill="#FCFCFA"/>`)
  parts.push(`<rect x="1" y="1" width="1078" height="1618" rx="18" fill="none" stroke="#DDD9D2"/>`)
  parts.push(`<circle cx="510" cy="465" r="320" fill="#F4E9DC" opacity=".20"/>`)

  parts.push(`<text x="40" y="62" font-family="system-ui,sans-serif" font-size="19" letter-spacing="4" fill="#6D6D69">TASTE PROFILE</text>`)
  parts.push(`<text x="40" y="119" font-family="system-ui,sans-serif" font-size="43" font-weight="780" fill="#202220">我的口味档案</text>`)
  parts.push(`<path d="M40 151 Q74 138 106 148 Q84 151 62 158" fill="none" stroke="#282A28" stroke-width="2"/>`)
  excerptLines(data.summary, 190, 17, 3).forEach((line, index) => parts.push(`<text data-poster-headline="true" x="40" y="${205 + index * 25}" font-family="system-ui,sans-serif" font-size="17" fill="#535952">${escapeXml(line)}</text>`))
  parts.push(`<rect x="28" y="310" width="195" height="104" rx="12" fill="#FFFFFF" stroke="#E4E0D9"/>`)
  parts.push(`<text x="48" y="344" font-family="system-ui,sans-serif" font-size="17" font-weight="720" fill="#333633">统计周期</text>`)
  const periodLines = taste.periodLabel.includes(' – ') ? taste.periodLabel.split(' – ') : excerptLines(taste.periodLabel, 155, 14, 2)
  periodLines.forEach((line, index) => parts.push(`<text x="48" y="${375 + index * 20}" font-family="system-ui,sans-serif" font-size="14" fill="#4F514E">${index ? '至 ' : ''}${escapeXml(line)}</text>`))
  if (taste.cuisineNote) posterTextLines(taste.cuisineNote, 170, 14).forEach((line, index) => parts.push(`<text data-poster-cuisine-scope="true" x="40" y="${466 + index * 22}" font-family="system-ui,sans-serif" font-size="14" fill="#77736E">${escapeXml(line)}</text>`))

  const cuisinePositions = [[505, 132], [675, 210], [723, 395], [682, 630], [505, 667], [320, 615], [250, 445]]
  taste.cuisines.slice(0, 7).forEach((item, index) => {
    const [x, y] = cuisinePositions[index]
    parts.push(`<line x1="505" y1="430" x2="${x}" y2="${y}" stroke="#BFC2BF" stroke-width="1.5" stroke-dasharray="6 7"/>`)
    parts.push(`<circle cx="${x}" cy="${y}" r="42" fill="#F8F3ED" stroke="#E2DDD5" filter="url(#tpSoft)"/>`)
    const artwork = prepared.cuisineArtwork?.[index]
    if (artwork) parts.push(`<clipPath id="tpCuisine${index}"><circle cx="${x}" cy="${y}" r="34"/></clipPath><image href="${artwork}" x="${x - 33}" y="${y - 33}" width="66" height="66" preserveAspectRatio="xMidYMid meet" clip-path="url(#tpCuisine${index})"/>`)
    parts.push(`<text x="${x}" y="${y + 70}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="27" font-weight="760" fill="#202220">${item.value}%</text>`)
    parts.push(`<text x="${x}" y="${y + 94}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="16" fill="#353735">${escapeXml(cut(item.label, 7))}</text>`)
  })
  if (!taste.cuisines.length) parts.push(`<text x="505" y="677" text-anchor="middle" font-family="system-ui,sans-serif" font-size="19" fill="#77736E">菜系尚未记录，不生成偏好比例</text>`)
  parts.push(`<circle cx="505" cy="430" r="181" fill="#FFFFFF" stroke="#E7DED3" stroke-width="2" filter="url(#tpShadow)"/>`)
  if (hero) parts.push(`<image href="${hero}" x="341" y="266" width="328" height="328" preserveAspectRatio="xMidYMid meet" clip-path="url(#tpHero)"/>`)
  else parts.push(`<circle cx="505" cy="430" r="164" fill="#F4E9DC"/><text x="505" y="443" text-anchor="middle" font-family="system-ui,sans-serif" font-size="24" fill="#686963">味觉记录</text>`)
  if (prepared.heroIsIllustration) parts.push(`<text x="505" y="617" text-anchor="middle" font-family="system-ui,sans-serif" font-size="12" fill="#77736E">素材插画 · 非餐厅实拍</text>`)

  parts.push(`<path d="M789 25 h236 v492 h-236 z" fill="#FFFFFF" stroke="#E1DDD5" filter="url(#tpShadow)"/>`)
  parts.push(`<path d="M789 25 ${Array.from({ length: 12 }, (_, index) => `q10 16 20 0`).join(' ')}" fill="none" stroke="#FCFCFA" stroke-width="11"/>`)
  parts.push(`<rect x="817" y="8" width="17" height="56" rx="9" fill="none" stroke="#B98250" stroke-width="3" transform="rotate(-17 825 36)"/>`)
  parts.push(`<text x="820" y="103" font-family="system-ui,sans-serif" font-size="27" font-weight="760" fill="#242624">数据总览</text>`)
  const overview = [
    ['restaurant', '记录餐厅', `${taste.restaurantCount} 家`],
    ['dish', '记录菜品', `${taste.dishCount} 道`],
    [null, '记录消费', taste.spend == null ? '未分享' : `¥${Math.round(taste.spend).toLocaleString('zh-CN')}`],
    ['city', '城市足迹', `${taste.cityCount} 个`],
  ] as const
  overview.forEach(([icon, label, value], index) => {
    const y = 154 + index * 68
    parts.push(`<line x1="817" y1="${y - 23}" x2="997" y2="${y - 23}" stroke="#E8E4DE"/>`)
    const artwork = icon ? prepared.objectArtwork?.[icon] : null
    if (artwork) parts.push(`<image data-poster-overview-icon="${icon}" href="${artwork}" x="809" y="${y - 8}" width="30" height="30" preserveAspectRatio="xMidYMid meet"/>`)
    if (!icon) parts.push(`<text x="824" y="${y + 14}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="22" fill="#B98250">¥</text>`)
    parts.push(`<text x="844" y="${y + 12}" font-family="system-ui,sans-serif" font-size="14" fill="#4A4C49">${label}</text>`)
    parts.push(`<text x="997" y="${y + 12}" text-anchor="end" font-family="system-ui,sans-serif" font-size="${value.length > 7 ? 15 : 21}" font-weight="700" fill="#252725">${escapeXml(value)}</text>`)
  })
  parts.push(`<line x1="817" y1="426" x2="997" y2="426" stroke="#BFB9B0" stroke-dasharray="5 5"/>`)
  parts.push(`<text x="820" y="466" font-family="system-ui,sans-serif" font-size="16" fill="#4A4C49">到访平均评分</text>`)
  parts.push(`<text x="994" y="496" text-anchor="end" font-family="system-ui,sans-serif" font-size="${taste.averageScoreOutOfTen == null ? 25 : 35}" font-weight="760" fill="#272927">${taste.averageScoreOutOfTen == null ? '未评分' : `${taste.averageScoreOutOfTen.toFixed(1)} <tspan font-size="16" font-weight="500" fill="#666963">/ 10</tspan>`}</text>`)

  parts.push(`<rect x="22" y="664" width="255" height="346" rx="13" fill="#FFFFFF" stroke="#E3DFD8"/>`)
  parts.push(`<text x="42" y="704" font-family="system-ui,sans-serif" font-size="22" font-weight="750" fill="#272927">最常吃 TOP 3</text><line x1="42" y1="719" x2="252" y2="719" stroke="#BDB9B2" stroke-dasharray="5 5"/>`)
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    const y = 795 + index * 82
    const rankColors = ['#E85E45', '#E59D42', '#8DA66B']
    parts.push(`<circle cx="53" cy="${y}" r="15" fill="${rankColors[index]}"/><text x="53" y="${y + 6}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="16" font-weight="750" fill="#FFFFFF">${index + 1}</text>`)
    if (restaurantImages[index]) parts.push(`<image href="${restaurantImages[index]}" x="81" y="${y - 31}" width="62" height="62" preserveAspectRatio="xMidYMid slice" clip-path="url(#tpRestaurant${index})"/>`)
    else parts.push(`<circle cx="112" cy="${y}" r="31" fill="#F4EBDD"/>`)
    excerptLines(restaurant.name, 100, 16, 2).forEach((line, lineIndex) => parts.push(`<text x="154" y="${y - 14 + lineIndex * 20}" font-family="system-ui,sans-serif" font-size="16" font-weight="720" fill="#2E302E">${escapeXml(line)}</text>`))
    parts.push(`<text x="154" y="${y + 30}" font-family="system-ui,sans-serif" font-size="12" fill="#77736E">${escapeXml(cut(restaurant.meta, restaurant.score ? 4 : 8))}</text>`)
    if (restaurant.score) parts.push(`<text data-poster-top-score="${index}" x="254" y="${y + 30}" text-anchor="end" font-family="system-ui,sans-serif" font-size="11" font-weight="650" fill="#D56749">${escapeXml(restaurant.score)} / 10</text>`)
  })
  if (!data.restaurants.length) parts.push(`<text x="42" y="797" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">尚无餐厅到访记录</text>`)

  parts.push(`<rect x="299" y="775" width="461" height="235" rx="13" fill="#FFFFFF" stroke="#E3DFD8"/>`)
  parts.push(`<text x="321" y="816" font-family="system-ui,sans-serif" font-size="22" font-weight="750" fill="#272927">口味偏好</text>`)
  taste.preferences.slice(0, 6).forEach((item, index) => {
    const x = 321 + (index + .5) * 414 / Math.min(6, taste.preferences.length)
    const artwork = prepared.preferenceArtwork?.[index]
    if (artwork) parts.push(`<image data-poster-preference-art="${escapeXml(item.label)}" href="${artwork}" x="${x - 25}" y="830" width="50" height="50" preserveAspectRatio="xMidYMid meet"/>`)
    else parts.push(posterTasteIcon(item.label, x - 25, 830))
    parts.push(`<text x="${x}" y="895" text-anchor="middle" font-family="system-ui,sans-serif" font-size="13" fill="#3F423F">${escapeXml(cut(item.label, 5))}</text>`)
    parts.push(`<rect x="${x - 22}" y="913" width="44" height="7" rx="4" fill="#E7E4DF"/><rect x="${x - 22}" y="913" width="${Math.max(0, Math.min(44, 44 * item.value / 100))}" height="7" rx="4" fill="#E87556"/>`)
    parts.push(`<text x="${x}" y="948" text-anchor="middle" font-family="system-ui,sans-serif" font-size="14" fill="#2E302E">${item.value}%</text>`)
  })
  if (!taste.preferences.length) parts.push(`<text x="321" y="892" font-family="system-ui,sans-serif" font-size="20" fill="#77736E">尚无菜品口味记录</text>`)

  parts.push(`<path d="M790 552 h246 v430 h-246 z" fill="#FFFCF5" stroke="#E9DFD0" filter="url(#tpSoft)"/>`)
  parts.push(`<path d="M777 563 l62 -42 l17 25 l-62 42 z" fill="#EEDFC5" opacity=".72"/>`)
  parts.push(`<text x="815" y="617" font-family="system-ui,sans-serif" font-size="27" font-weight="760" fill="#282A28">口味发现</text>`)
  const findings = posterFindings(data).slice(0, 3)
  findings.forEach((insight, index) => {
    const y = 667 + index * 96
    parts.push(`<circle cx="820" cy="${y - 7}" r="10" fill="none" stroke="#87918A"/><text x="820" y="${y - 3}" text-anchor="middle" font-size="10" fill="#647068">✓</text>`)
    excerptLines(insight, 166, 15, 4).forEach((line, lineIndex) => parts.push(`<text data-poster-finding="${index}" x="845" y="${y + lineIndex * 20}" font-family="system-ui,sans-serif" font-size="15" fill="#3D403D">${escapeXml(line)}</text>`))
  })
  if (!findings.length) parts.push(`<text x="815" y="688" font-family="system-ui,sans-serif" font-size="17" fill="#77736E">记录还在积累</text><text x="815" y="718" font-family="system-ui,sans-serif" font-size="15" fill="#77736E">不补没有依据的结论</text>`)
  parts.push(`<path d="M1002 948 h34 v34 h-34 z" fill="#F1E3CB"/><path d="M1002 982 l34 -34 v34 z" fill="#FFF9EF"/>`)

  parts.push(`<rect x="22" y="1032" width="326" height="274" rx="13" fill="#FFFFFF" stroke="#E3DFD8"/>`)
  parts.push(`<text x="42" y="1074" font-family="system-ui,sans-serif" font-size="21" font-weight="750" fill="#292B29">消费分布</text><line x1="42" y1="1090" x2="170" y2="1090" stroke="#BDB9B2" stroke-dasharray="5 5"/>`)
  const circumference = 263.89
  let consumed = 0
  const donutColors = ['#ED7458', '#E6A15B', '#92AB7A', '#8EAEBE', '#D9B994']
  taste.spendCategories.slice(0, 5).forEach((item, index) => {
    const length = circumference * item.value / 100
    parts.push(`<circle cx="112" cy="1182" r="42" fill="none" stroke="${donutColors[index]}" stroke-width="22" stroke-dasharray="${length} ${circumference - length}" stroke-dashoffset="${-circumference * consumed / 100}" transform="rotate(-90 112 1182)"/>`)
    consumed += item.value
  })
  if (taste.spendCategories.length) parts.push(`<circle cx="112" cy="1182" r="26" fill="#FFFFFF"/><text x="112" y="1187" text-anchor="middle" font-family="system-ui,sans-serif" font-size="11" fill="#666963">消费占比</text>`)
  taste.spendCategories.slice(0, 5).forEach((item, index) => {
    const y = 1120 + index * 32
    parts.push(`<circle cx="184" cy="${y - 5}" r="4" fill="${donutColors[index]}"/><text x="194" y="${y}" font-family="system-ui,sans-serif" font-size="12" fill="#454745">${escapeXml(cut(item.label, 7))}</text><text x="328" y="${y}" text-anchor="end" font-family="system-ui,sans-serif" font-size="12" fill="#2D302D">${Math.round(item.value)}%</text>`)
  })

  parts.push(`<path d="M367 1032 h228 v274 h-228 z" fill="#FFFFFF" stroke="#E3DFD8" filter="url(#tpSoft)"/>`)
  parts.push(`<text x="389" y="1074" font-family="system-ui,sans-serif" font-size="21" font-weight="750" fill="#292B29">人均消费区间</text><line x1="389" y1="1090" x2="565" y2="1090" stroke="#BDB9B2" stroke-dasharray="5 5"/>`)
  const leadingPrice = Math.max(...taste.priceRanges.map((item) => item.value))
  taste.priceRanges.slice(0, 7).forEach((item, index) => {
    const y = 1121 + index * 24
    const active = item.value === leadingPrice && leadingPrice > 0
    parts.push(`<circle cx="393" cy="${y - 5}" r="3" fill="${active ? '#E55A43' : '#A5B9C2'}"/><text x="408" y="${y}" font-family="system-ui,sans-serif" font-size="${active ? 17 : 14}" font-weight="${active ? 720 : 500}" fill="${active ? '#E5543E' : '#4E514E'}">${escapeXml(item.label)}</text><text x="571" y="${y}" text-anchor="end" font-family="system-ui,sans-serif" font-size="${active ? 17 : 14}" font-weight="${active ? 720 : 500}" fill="${active ? '#E5543E' : '#4E514E'}">${item.value}%</text>`)
  })
  if (!data.privacy.spendIncluded) {
    parts.push(`<text x="184" y="1190" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">消费详情未分享</text>`)
    parts.push(`<text x="184" y="1224" text-anchor="middle" font-family="system-ui,sans-serif" font-size="14" fill="#8A8279">完整记录保留在数据版</text>`)
    parts.push(`<text x="480" y="1190" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">价位详情未分享</text>`)
  } else {
    if (!taste.spendCategories.length) parts.push(`<text x="184" y="1190" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">暂无可统计的消费分布</text>`)
    if (!taste.priceRanges.length) parts.push(`<text x="480" y="1190" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">尚无可靠人均记录</text>`)
  }
  parts.push(`<path d="M392 1282 h176" stroke="#2D2F2D" stroke-width="12" stroke-dasharray="2 3 5 2 1 4"/>`)

  parts.push(`<rect x="615" y="1032" width="421" height="274" rx="13" fill="#FFFFFF" stroke="#E3DFD8"/>`)
  parts.push(`<text x="637" y="1074" font-family="system-ui,sans-serif" font-size="21" font-weight="750" fill="#292B29">城市足迹 TOP 5</text><line x1="637" y1="1090" x2="812" y2="1090" stroke="#BDB9B2" stroke-dasharray="5 5"/>`)
  taste.cities.slice(0, 5).forEach((item, index) => {
    const y = 1125 + index * 33
    parts.push(`<circle cx="646" cy="${y - 5}" r="10" fill="${index < 3 ? '#E76A50' : '#83A1AE'}"/><text x="646" y="${y - 1}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="10" font-weight="720" fill="#FFFFFF">${index + 1}</text><text x="665" y="${y}" font-family="system-ui,sans-serif" font-size="14" fill="#343734">${escapeXml(cut(item.label, 7))}</text><text x="808" y="${y}" text-anchor="end" font-family="system-ui,sans-serif" font-size="13" fill="#343734">${item.value} 家</text>`)
  })
  if (!taste.cities.length) parts.push(`<text x="637" y="1140" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">城市尚未记录</text>`)
  if (prepared.objectArtwork?.city) parts.push(`<image data-poster-city-decoration="true" href="${prepared.objectArtwork.city}" x="846" y="1124" width="152" height="152" preserveAspectRatio="xMidYMid meet"/>`)
  parts.push(`<text x="846" y="1290" font-family="system-ui,sans-serif" font-size="11" fill="#8A8279">地图插画 · 非真实定位</text>`)

  parts.push(`<rect x="22" y="1330" width="490" height="240" rx="13" fill="#FFFFFF" stroke="#E3DFD8"/>`)
  parts.push(`<text x="42" y="1372" font-family="system-ui,sans-serif" font-size="21" font-weight="750" fill="#292B29">常见饭搭子  ♡</text>`)
  taste.companions.slice(0, 4).forEach((item, index) => {
    const x = 42 + (index + .5) * 440 / Math.min(4, taste.companions.length)
    parts.push(`<text x="${x}" y="1420" text-anchor="middle" font-family="system-ui,sans-serif" font-size="14" fill="#373A37">${escapeXml(cut(item.label, 6))}</text>`, posterIcon('people', x - 28, 1440, 56), `<text x="${x}" y="1530" text-anchor="middle" font-family="system-ui,sans-serif" font-size="24" font-weight="720" fill="#252725">${item.value}%</text>`)
  })
  if (!taste.companions.length) parts.push(`<text x="267" y="1470" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">${data.privacy.companionNameIncluded ? '尚无同行记录' : '同行信息未分享'}</text>`)

  parts.push(`<rect x="531" y="1330" width="505" height="240" rx="13" fill="#FFFFFF" stroke="#E3DFD8"/>`)
  parts.push(`<text x="553" y="1372" font-family="system-ui,sans-serif" font-size="21" font-weight="750" fill="#292B29">用餐时间偏好</text>`)
  taste.diningTimes.slice(0, 5).forEach((item, index) => {
    const x = 580 + index * 96
    parts.push(posterIcon(item.label === '夜宵' ? 'moon' : item.label === '晚餐' || item.label === '下午茶' ? 'clock' : 'sun', x - 22, 1401, 44))
    parts.push(`<text x="${x}" y="1470" text-anchor="middle" font-family="system-ui,sans-serif" font-size="14" fill="#3E413E">${escapeXml(item.label)}</text><text x="${x}" y="1511" text-anchor="middle" font-family="system-ui,sans-serif" font-size="25" font-weight="730" fill="#E65B43">${item.value}%</text>`)
  })
  if (!taste.diningTimes.length) parts.push(`<text x="783" y="1465" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" fill="#77736E">尚无可分析的用餐时刻</text>`)
  if (taste.diningTimeNote) parts.push(`<text x="553" y="1547" font-family="system-ui,sans-serif" font-size="13" fill="#77736E">${escapeXml(taste.diningTimeNote)}</text>`)
  if (logo) parts.push(`<image href="${logo}" x="16" y="1580" width="18" height="18"/>`)
  parts.push(`<text x="40" y="1597" font-family="system-ui,sans-serif" font-size="12" fill="#8A8279">${escapeXml(data.footer)}</text><text x="1038" y="1597" text-anchor="end" font-family="system-ui,sans-serif" font-size="12" fill="#B56A4F">所有数据均来自你的真实记录</text>`)
  parts.push(`</svg>`)
  return parts.join('')
}

export async function renderAnalysisPosterBlob(data: AnalysisShareData, heroIndex = 0) {
  const prepared = await prepareAnalysisPoster(data, heroIndex)
  const svg = renderAnalysisPosterSvg(prepared)
  const svgBlob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' })
  const url = URL.createObjectURL(svgBlob)
  try {
    const image = new Image()
    image.decoding = 'async'
    image.src = url
    await image.decode()
    const canvas = document.createElement('canvas')
    canvas.width = POSTER_WIDTH
    canvas.height = data.editorial ? EDITORIAL_POSTER_HEIGHT : data.type === 'TASTE_PROFILE' && data.tasteProfile ? TASTE_PROFILE_POSTER_HEIGHT : POSTER_HEIGHT
    canvas.getContext('2d')?.drawImage(image, 0, 0)
    return await new Promise<Blob>((resolve, reject) => canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('海报生成失败')), 'image/png', .94))
  } finally {
    URL.revokeObjectURL(url)
  }
}

export function analysisPosterFilename(data: AnalysisShareData) {
  return `taste-map-${data.type.toLowerCase().replace(/_/g, '-')}-${data.reportId.split(':').slice(-1)[0]}.png`
}

export function downloadAnalysisPoster(blob: Blob, data: AnalysisShareData) {
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = analysisPosterFilename(data)
  anchor.click()
  window.setTimeout(() => URL.revokeObjectURL(url), 1500)
}

export async function shareAnalysisPoster(blob: Blob, data: AnalysisShareData) {
  const file = new File([blob], analysisPosterFilename(data), { type: 'image/png' })
  if (navigator.share && (!navigator.canShare || navigator.canShare({ files: [file] }))) {
    await navigator.share({ title: data.title, text: data.summary, files: [file] })
    return true
  }
  downloadAnalysisPoster(blob, data)
  return false
}
