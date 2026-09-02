import type { AnalysisShareData } from '../types/analysisShare'
import { filterAnalysisSharePrivacy } from './analysisShare'
import { resolveVisualForPoster } from './foodVisualResolver'

export const POSTER_WIDTH = 1080
export const POSTER_HEIGHT = 1920

export interface PreparedAnalysisPoster {
  data: AnalysisShareData
  hero: string | null
  logo: string | null
  restaurantImages: Array<string | null>
  heroIndex: number
}

const escapeXml = (value: string) => value.replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[character] || character))
const cut = (value: string, length: number) => value.length > length ? `${value.slice(0, length - 1)}…` : value

export async function prepareAnalysisPoster(data: AnalysisShareData, heroIndex = 0): Promise<PreparedAnalysisPoster> {
  const safeData = filterAnalysisSharePrivacy(data)
  const index = safeData.heroCandidates.length ? ((heroIndex % safeData.heroCandidates.length) + safeData.heroCandidates.length) % safeData.heroCandidates.length : 0
  const [hero, logo, restaurantImages] = await Promise.all([
    resolveVisualForPoster(safeData.heroCandidates[index]),
    resolveVisualForPoster({ source: safeData.logoSource, photoId: null, origin: 'restaurant', label: 'Taste Map' }),
    Promise.all(safeData.restaurants.slice(0, 3).map((restaurant) => resolveVisualForPoster(restaurant.image))),
  ])
  return { data: safeData, hero, logo, restaurantImages, heroIndex: index }
}

export function renderAnalysisPosterSvg(prepared: PreparedAnalysisPoster) {
  const { data, hero, logo, restaurantImages } = prepared
  const themes: Record<AnalysisShareData['type'], { accent: string; soft: string; symbol: string }> = {
    TASTE_PROFILE: { accent: '#D56749', soft: '#F7E6D6', symbol: '口味画像' },
    COMPANION_ANALYSIS: { accent: '#A96656', soft: '#F3E1DA', symbol: '一起吃饭' },
    RECOMMENDATION_SOURCE: { accent: '#B0793E', soft: '#F4E8D0', symbol: '推荐验证' },
    MONTHLY_REVIEW: { accent: '#647F78', soft: '#E2ECE7', symbol: '月度回味' },
    ANNUAL_REVIEW: { accent: '#506C8C', soft: '#E2E9F0', symbol: '年度轨迹' },
    ON_THIS_DAY: { accent: '#876D8E', soft: '#EDE4EF', symbol: '味觉记忆' },
  }
  const theme = themes[data.type]
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
  parts.push(`<text x="82" y="369" font-family="system-ui,sans-serif" font-size="18" font-weight="720" fill="${theme.accent}">${theme.symbol}</text>`)
  const summary = data.summary.trim()
  for (let index = 0; index < 2; index += 1) {
    const line = summary.slice(index * 37, (index + 1) * 37)
    if (line) parts.push(`<text x="82" y="${403 + index * 31}" font-family="system-ui,sans-serif" font-size="24" font-weight="620" fill="#33434D">${escapeXml(cut(line, 37))}</text>`)
  }
  const nodePositions = [[165, 540], [890, 535], [105, 735], [975, 738], [225, 930], [835, 938]]
  nodePositions.forEach(([x, y], index) => {
    const metric = data.metrics[index % Math.max(data.metrics.length, 1)]
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
  parts.push(`<rect x="56" y="1050" width="626" height="292" rx="26" fill="#FFFFFF" stroke="#E8E2DA"/>`)
  parts.push(`<text x="84" y="1101" font-family="system-ui,sans-serif" font-size="28" font-weight="740" fill="#2C353B">近期洞察</text>`)
  data.insights.slice(0, 4).forEach((insight, index) => {
    parts.push(`<circle cx="94" cy="${1150 + index * 48}" r="7" fill="${index === 0 ? theme.accent : '#78909E'}"/>`)
    parts.push(`<text x="118" y="${1158 + index * 48}" font-family="system-ui,sans-serif" font-size="22" fill="#40515B">${escapeXml(cut(insight, 34))}</text>`)
  })
  parts.push(`<rect x="704" y="1050" width="320" height="292" rx="26" fill="${theme.soft}" fill-opacity=".68" stroke="#E5DDD3"/>`)
  parts.push(`<text x="730" y="1101" font-family="system-ui,sans-serif" font-size="28" font-weight="740" fill="#2C353B">TOP 3</text>`)
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    parts.push(`<circle cx="750" cy="${1151 + index * 58}" r="18" fill="${theme.accent}"/><text x="750" y="${1159 + index * 58}" text-anchor="middle" font-family="system-ui,sans-serif" font-size="17" font-weight="750" fill="#FFFFFF">${index + 1}</text><text x="782" y="${1158 + index * 58}" font-family="system-ui,sans-serif" font-size="21" font-weight="650" fill="#3E464B">${escapeXml(cut(restaurant.name, 12))}</text>`)
  })
  if (data.restaurants.length) parts.push(`<text x="56" y="1402" font-family="system-ui,sans-serif" font-size="29" font-weight="740" fill="#2C353B">代表餐厅</text>`)
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    const x = 56 + index * 328
    parts.push(`<rect x="${x}" y="1432" width="304" height="326" rx="24" fill="#FFFFFF" stroke="#E8E2DA"/>`)
    if (restaurantImages[index]) parts.push(`<image href="${restaurantImages[index]}" x="${x}" y="1432" width="304" height="204" preserveAspectRatio="xMidYMid slice" clip-path="inset(0 round 24px 24px 0 0)"/>`)
    else parts.push(`<rect x="${x}" y="1432" width="304" height="204" rx="24" fill="${theme.soft}"/><text x="${x + 152}" y="1546" text-anchor="middle" font-family="system-ui,sans-serif" font-size="20" fill="#796F67">暂无真实图片</text>`)
    parts.push(`<text x="${x + 18}" y="1681" font-family="system-ui,sans-serif" font-size="22" font-weight="720" fill="#2C353B">${escapeXml(cut(restaurant.name, 12))}</text>`)
    parts.push(`<text x="${x + 18}" y="1718" font-family="system-ui,sans-serif" font-size="17" fill="#7B7772">${escapeXml(cut(restaurant.meta, 20))}</text>`)
  })
  parts.push(`<line x1="56" y1="1832" x2="1024" y2="1832" stroke="#DED8D0"/>`)
  parts.push(`<text x="56" y="1877" font-family="system-ui,sans-serif" font-size="19" fill="#7B7772">${escapeXml(data.footer)}</text>`)
  parts.push(`<text x="1024" y="1877" text-anchor="end" font-family="system-ui,sans-serif" font-size="18" fill="${theme.accent}">基于真实记录生成</text>`)
  parts.push('</svg>')
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
    canvas.height = POSTER_HEIGHT
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
