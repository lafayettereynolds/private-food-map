import type { AnalysisShareData } from '../types/analysisShare'
import { filterAnalysisSharePrivacy } from './analysisShare'
import { resolveVisualForPoster } from './foodVisualResolver'

export const POSTER_WIDTH = 1080
export const POSTER_HEIGHT = 1440

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
  const parts: string[] = [`<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1440" viewBox="0 0 1080 1440">`]
  parts.push(`<defs><linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#172A3A" stop-opacity=".08"/><stop offset="1" stop-color="#172A3A" stop-opacity=".76"/></linearGradient></defs>`)
  parts.push(`<rect width="1080" height="1440" fill="#F7F7F5"/>`)
  if (hero) parts.push(`<image href="${hero}" width="1080" height="450" preserveAspectRatio="xMidYMid slice"/>`)
  else parts.push(`<rect width="1080" height="450" fill="#506C8C"/>`)
  parts.push(`<rect width="1080" height="450" fill="url(#shade)"/>`)
  parts.push(`<rect x="56" y="48" width="242" height="70" rx="35" fill="#FFFFFF" fill-opacity=".94"/>`)
  if (logo) parts.push(`<image href="${logo}" x="68" y="57" width="52" height="52"/>`)
  parts.push(`<text x="132" y="94" font-family="system-ui,sans-serif" font-size="28" font-weight="700" fill="#172A3A">Taste Map</text>`)
  parts.push(`<text x="60" y="318" font-family="system-ui,sans-serif" font-size="22" letter-spacing="5" fill="#FFFFFF" opacity=".88">${escapeXml(data.eyebrow)}</text>`)
  parts.push(`<text x="58" y="380" font-family="system-ui,sans-serif" font-size="58" font-weight="750" fill="#FFFFFF">${escapeXml(cut(data.title, 18))}</text>`)
  parts.push(`<text x="60" y="422" font-family="system-ui,sans-serif" font-size="25" fill="#FFFFFF" opacity=".86">${escapeXml(cut(data.subtitle, 38))}</text>`)
  parts.push(`<rect x="44" y="426" width="992" height="970" rx="38" fill="#FFFFFF"/>`)
  parts.push(`<text x="78" y="502" font-family="system-ui,sans-serif" font-size="28" font-weight="700" fill="#506C8C">本页结论</text>`)
  const summary = data.summary.trim()
  for (let index = 0; index < 3; index += 1) {
    const line = summary.slice(index * 25, (index + 1) * 25)
    if (line) parts.push(`<text x="78" y="${556 + index * 40}" font-family="system-ui,sans-serif" font-size="31" font-weight="650" fill="#172A3A">${escapeXml(cut(line, 25))}</text>`)
  }
  data.metrics.slice(0, 4).forEach((metric, index) => {
    const x = 70 + index * 242
    const isWorst = metric.label === '最坑'
    parts.push(`<line x1="${x}" y1="675" x2="${x + 204}" y2="675" stroke="#E3E6E8"/>`)
    parts.push(`<text x="${x}" y="716" font-family="system-ui,sans-serif" font-size="20" fill="${isWorst ? '#A66F4F' : '#727C84'}">${escapeXml(metric.label)}</text>`)
    parts.push(`<text x="${x}" y="766" font-family="system-ui,sans-serif" font-size="38" font-weight="750" fill="${isWorst ? '#B87957' : '#344F69'}">${escapeXml(metric.value)}</text>`)
  })
  parts.push(`<text x="78" y="830" font-family="system-ui,sans-serif" font-size="28" font-weight="700" fill="#172A3A">真实记录里的洞察</text>`)
  data.insights.slice(0, 4).forEach((insight, index) => {
    parts.push(`<circle cx="89" cy="${878 + index * 40}" r="6" fill="${index === 0 ? '#D09A63' : '#506C8C'}"/>`)
    parts.push(`<text x="112" y="${886 + index * 40}" font-family="system-ui,sans-serif" font-size="23" fill="#344F69">${escapeXml(cut(insight, 37))}</text>`)
  })
  if (data.restaurants.length) parts.push(`<text x="78" y="1058" font-family="system-ui,sans-serif" font-size="28" font-weight="700" fill="#172A3A">代表餐厅</text>`)
  data.restaurants.slice(0, 3).forEach((restaurant, index) => {
    const x = 78 + index * 312
    parts.push(`<rect x="${x}" y="1090" width="286" height="218" rx="22" fill="#F7F7F5"/>`)
    if (restaurantImages[index]) parts.push(`<image href="${restaurantImages[index]}" x="${x}" y="1090" width="286" height="132" preserveAspectRatio="xMidYMid slice" clip-path="inset(0 round 22px 22px 0 0)"/>`)
    else parts.push(`<rect x="${x}" y="1090" width="286" height="132" rx="22" fill="#EDF2F6"/>`)
    parts.push(`<text x="${x + 16}" y="1253" font-family="system-ui,sans-serif" font-size="21" font-weight="700" fill="#172A3A">${escapeXml(cut(restaurant.name, 11))}</text>`)
    parts.push(`<text x="${x + 16}" y="1282" font-family="system-ui,sans-serif" font-size="16" fill="#727C84">${escapeXml(cut(restaurant.meta, 17))}</text>`)
  })
  parts.push(`<line x1="70" y1="1360" x2="1010" y2="1360" stroke="#E3E6E8"/>`)
  parts.push(`<text x="70" y="1395" font-family="system-ui,sans-serif" font-size="20" fill="#727C84">${escapeXml(data.footer)}</text>`)
  parts.push(`<text x="1010" y="1395" text-anchor="end" font-family="system-ui,sans-serif" font-size="18" fill="#506C8C">基于真实记录生成</text>`)
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
