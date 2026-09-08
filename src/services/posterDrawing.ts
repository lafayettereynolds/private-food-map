export const posterInk = '#303830'
export const posterMuted = '#767b73'
export const posterFont = 'system-ui, -apple-system, sans-serif'
/** Semantic flavor glyphs for structured taste tags, not inferred food evidence. */
export function posterTasteIcon(label: string, x: number, y: number, size = 50) {
  const shape = /辣/.test(label)
    ? '<path d="M42 13C56 28 37 55 10 55c17-8 17-20 24-34Z" fill="#E96949"/><path d="M36 20c-1-9 4-14 11-13" stroke="#738952" stroke-width="5"/><path d="M36 30c-3 8-8 14-14 17" stroke="#FFC5A5"/>'
    : /酸/.test(label)
      ? '<ellipse cx="32" cy="33" rx="24" ry="23" fill="#F1CF73"/><circle cx="32" cy="33" r="17" fill="#FFF4CB"/><path d="M32 16v34M15 33h34M20 21l24 24M20 45l24-24" stroke="#D9B45F"/>'
      : /鲜/.test(label)
        ? '<path d="M31 19C3 8 4 53 27 56c24 7 37-36 12-38Z" fill="#E87E5F"/><path d="m32 22-12-7 11 1 2-10 3 11 11-2-10 8Z" fill="#80965C"/><path d="M19 29c-3 5-3 10-1 14" stroke="#FFD2B8"/>'
        : null
  return shape ? `<svg data-poster-flavor-icon="${escapePosterText(label)}" x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 64 64"><g stroke="#80644E" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${shape}</g></svg>` : ''
}
export const escapePosterText = (value: string) => value.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]!)
let measureContext: CanvasRenderingContext2D | null | undefined
export function posterTextWidth(text: string, size: number, weight = 400) {
  if (measureContext === undefined) measureContext = typeof document === 'undefined' ? null : document.createElement('canvas').getContext('2d')
  if (measureContext) { measureContext.font = `${weight} ${size}px ${posterFont}`; return measureContext.measureText(text).width }
  return Array.from(text).reduce((sum, char) => sum + (/[^\u0000-\u00ff]/.test(char) ? size : size * .64), 0)
}
export function posterLines(text: string, width: number, size: number, maxLines: number, weight = 400) {
  const result: string[] = []; let line = ''
  for (const char of Array.from(text)) {
    if (char === '\n' || (line && posterTextWidth(line + char, size, weight) > width)) { result.push(line); line = char === '\n' ? '' : char }
    else line += char
  }
  if (line) result.push(line)
  if (result.length <= maxLines) return result
  const visible = result.slice(0, maxLines)
  let last = visible[maxLines - 1]
  while (last && posterTextWidth(last + '…', size, weight) > width) last = Array.from(last).slice(0, -1).join('')
  visible[maxLines - 1] = last + '…'
  return visible
}
export function posterText(text: string, x: number, y: number, width: number, size = 18, maxLines = 2, weight = 400, color = posterInk, anchor = 'start') {
  const lines = posterLines(text, width, size, maxLines, weight)
  return `<text x="${x}" y="${y}" font-family="${posterFont}" font-size="${size}" font-weight="${weight}" fill="${color}" text-anchor="${anchor}">${lines.map((line, index) => `<tspan x="${x}" dy="${index ? size * 1.45 : 0}">${escapePosterText(line)}</tspan>`).join('')}</text>`
}
export function posterIcon(id: 'store' | 'plate' | 'wallet' | 'pin' | 'bulb' | 'sun' | 'moon' | 'people' | 'calendar' | 'clock', x: number, y: number, size = 30) {
  const shapes = {
    store: '<path d="M12 38V20h40v38H12z" fill="#fff9ed"/><path d="M9 24l5-15h36l5 15c-4 7-10 7-14 0-5 7-12 7-17 0-5 7-11 7-15 0Z" fill="#eeb9a0"/><path d="M26 58V39h13v19"/>',
    plate: '<path d="M7 48h50M12 43a20 20 0 0 1 40 0H12Z" fill="#fcf8ef"/><path d="M29 20v-5h6v5M8 53h48"/>',
    wallet: '<path d="M10 19 45 9v14M9 23h45v32H9z" fill="#eedbbb"/><path d="M40 33h18v13H40z" fill="#fffcf6"/><circle cx="46" cy="39" r="1.5"/>',
    pin: '<path d="M32 58S13 35 13 24a19 19 0 0 1 38 0c0 11-19 34-19 34Z" fill="#eab29b"/><circle cx="32" cy="24" r="7" fill="#fffaf4"/>',
    bulb: '<path d="M23 43C5 28 16 11 32 11s27 17 9 32l-3 9H26z" fill="#fff2c8"/><path d="M27 57h10M32 5V1M10 13 5 8M54 13l5-5M5 31H1M59 31h4M27 28l5 14 5-14"/>',
    sun: '<circle cx="32" cy="32" r="15" fill="#f2cf7f"/><path d="M32 3v7M32 54v7M3 32h7M54 32h7M11 11l5 5M48 48l5 5M11 53l5-5M48 16l5-5"/>',
    moon: '<path d="M43 7C20 32 37 43 56 38 49 60 15 57 11 36 7 19 25 4 43 7Z" fill="#e6d193"/>',
    people: '<circle cx="24" cy="22" r="10" fill="#eac8ae"/><path d="M6 58V48c0-22 36-22 36 0v10" fill="#b9c4ad"/><circle cx="46" cy="26" r="8" fill="#eac8ae"/><path d="M44 41c11-3 16 5 16 16"/>',
    calendar: '<rect x="9" y="13" width="46" height="44" rx="5" fill="#fffcf6"/><path d="M9 25h46M21 6v14M43 6v14M20 35h6M36 35h6M20 46h6"/>',
    clock: '<circle cx="32" cy="32" r="26" fill="#fffcf6"/><path d="M32 10v5M32 49v5M10 32h5M49 32h5M32 20v14l12 6"/>',
  }
  return `<svg data-poster-icon="${id}" x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 64 64"><g stroke="#675d4d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none">${shapes[id]}</g></svg>`
}
