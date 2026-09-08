import type { AnalysisEditorialRow, AnalysisEditorialSection } from '../types/analysisShare'
import type { PreparedAnalysisPoster } from './analysisPosterRenderer'
import { escapePosterText as esc, posterLines, posterIcon, posterTextWidth } from './posterDrawing'

/** Canonical scrapbook canvas dimensions follow the supplied near-A-series sheets. */
export const EDITORIAL_POSTER_HEIGHT = 1530
const ink = '#282b29', muted = '#7d807a', coral = '#e87555'
const colors = ['#ec7656', '#e9ab59', '#95ac7e', '#85a9b8', '#bea6ae', '#91b4a5']
const text = (label: string, x: number, y: number, size = 18, weight = 400, color = ink, anchor = 'start') => `<text x="${x}" y="${y}" font-family="system-ui,-apple-system,sans-serif" font-size="${size}" font-weight="${weight}" fill="${color}" text-anchor="${anchor}">${esc(label)}</text>`
const lines = (label: string, x: number, y: number, width: number, size = 18, count = 2, color = muted, weight = 400) => posterLines(label, width, size, count, weight).map((line, i) => text(line, x, y + i * (size * 1.45), size, weight, color)).join('')
const image = (url: string | null | undefined, x: number, y: number, w: number, h: number, photo = false) => url ? `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" overflow="hidden"><image href="${esc(url)}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid ${photo ? 'slice' : 'meet'}"/></svg>` : ''

export function renderEditorialPoster(prepared: PreparedAnalysisPoster) {
  const { data, hero, logo } = prepared, sheet = data.editorial!
  const out: string[] = [`<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1530" viewBox="0 0 1080 1530"><defs><filter id="paperShadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="5" stdDeviation="7" flood-color="#80654d" flood-opacity=".10"/></filter><pattern id="paperGrain" width="31" height="29" patternUnits="userSpaceOnUse"><circle cx="5" cy="7" r=".7" fill="#a88c68" opacity=".045"/><circle cx="22" cy="19" r=".5" fill="#c3b191" opacity=".07"/></pattern></defs><rect width="1080" height="1530" rx="16" fill="#fdfcf8"/><rect width="1080" height="1530" rx="16" fill="url(#paperGrain)"/><rect x="1" y="1" width="1078" height="1528" rx="16" fill="none" stroke="#e2ded6"/>`]
  const find = (id: string) => sheet.sections.find(section => section.id === id) ?? { id, title: '', rows: [] }
  const art = (id: string, index: number) => prepared.editorialArtwork?.[`${id}:${index}`]
  const tape = (x: number, y: number, angle = -9) => `<path d="M${x} ${y}h72l-2 24h-71z" fill="#efd8ac" opacity=".65" transform="rotate(${angle} ${x + 36} ${y + 12})"/>`
  const card = (x: number, y: number, w: number, h: number, tone = '#fffefb', receipt = false) => {
    out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="10" fill="${tone}" stroke="#e6e2da" ${receipt ? 'filter="url(#paperShadow)"' : ''}/>`)
    if (receipt) { for (let cx = x + 20; cx < x + w - 10; cx += 28) out.push(`<circle cx="${cx}" cy="${y}" r="6" fill="#fdfcf8"/>`); out.push(`<rect x="${x + 25}" y="${y - 12}" width="15" height="50" rx="7" transform="rotate(-20 ${x + 32} ${y + 10})" fill="none" stroke="#ba9367" stroke-width="2.5"/>`) }
  }
  const heading = (value: string, x: number, y: number, w: number, icon?: Parameters<typeof posterIcon>[0]) => { if (icon) out.push(posterIcon(icon, x, y - 24, 28)); out.push(lines(value, x + (icon ? 36 : 0), y, w - (icon ? 36 : 0), 21, 1, ink, 700), `<path d="M${x} ${y + 15}h${w}" stroke="#d7d1c7" stroke-dasharray="4 4"/>`) }
  const title = (value: string, eyebrow: string) => {
    out.push(text(eyebrow, 36, 49, 18, 400, muted), text(value, 36, 122, 57, 770), `<path d="M38 153q26-10 44-4l-8 8 47-3" fill="none" stroke="${ink}" stroke-width="2"/>`)
  }
  const note = (value: string, x: number, y: number, w: number, h: number, angle = -3) => {
    out.push(`<g transform="rotate(${angle} ${x + w / 2} ${y + h / 2})">`); card(x, y, w, h, '#fff8e9', true)
    out.push(tape(x + w * .6, y - 10), lines(value, x + 24, y + 47, w - 48, 21, Math.floor((h - 35) / 31), '#766046', 500), '</g>')
  }
  const overview = (x: number, y: number, w: number, h: number, caption: string) => {
    card(x, y, w, h, '#fffefa', true); heading(caption, x + 24, y + 62, w - 48)
    const step = (h - 133) / Math.max(1, sheet.overview.length)
    sheet.overview.forEach((item, i) => {
      const yy = y + 112 + i * step
      out.push(posterIcon((['plate','store','wallet','bulb','pin'] as const)[i] ?? 'clock', x + 22, yy - 20, 26), text(item.label, x + 60, yy, 16, 400, muted), text(item.value, x + w - 23, yy + 27, 24, 700, ink, 'end'))
      if (item.note) out.push(text(item.note, x + 60, yy + 26, 11, 400, muted))
      if (i < sheet.overview.length - 1) out.push(`<path d="M${x + 24} ${yy + 43}h${w - 48}" stroke="#eeebe4"/>`)
    })
  }
  const ranked = (id: string, x: number, y: number, w: number, h: number, options: { title?: string; max?: number; negative?: boolean; photos?: boolean; bars?: boolean } = {}) => {
    const section = find(id), rows = section.rows.slice(0, options.max ?? 3)
    card(x, y, w, h, options.negative ? '#fff4ef' : '#fffefa'); heading(options.title ?? section.title, x + 20, y + 37, w - 40)
    if (section.note) out.push(lines(section.note, x + 20, y + 75, w - 40, 12, 2))
    if (!rows.length) { out.push(lines(section.empty ?? '暂无相关记录', x + 24, y + h / 2 + 12, w - 48, 17, 3)); return }
    if (options.max === 1 && w < 310 && h < 330) {
      const row = rows[0]
      out.push(image(art(id, 0), x + 22, y + 85, w - 44, h - 168, row.visual?.origin === 'visit'), lines(row.label, x + 20, y + h - 57, w - 40, 17, 2, ink, 650), lines([row.value, row.detail].filter(Boolean).join(' · '), x + 20, y + h - 17, w - 40, 12, 1))
      return
    }
    const start = y + (section.note ? 110 : 80), step = (y + h - 18 - start) / rows.length
    const max = Math.max(...rows.map(row => row.amount ?? 0), 1)
    rows.forEach((row, i) => {
      const yy = start + i * step, tight = step < 68
      out.push(`<circle cx="${x + 29}" cy="${yy + 10}" r="12" fill="${colors[i % colors.length]}"/>`, text(String(i + 1), x + 29, yy + 15, 14, 600, '#fff', 'middle'))
      const asset = art(id, i), thumb = options.photos !== false && asset ? Math.min(66, step - 13) : 0
      if (thumb) out.push(image(asset, x + 48, yy - 14, thumb, thumb, row.visual?.origin === 'visit'))
      const left = x + 49 + (thumb ? thumb + 8 : 0), width = x + w - 20 - left
      const stacked = !options.bars && posterTextWidth(row.value, 16, 650) > 85
      const reserve = stacked || options.bars ? 0 : Math.max(48, posterTextWidth(row.value, 16, 650) + 12)
      out.push(lines(row.label, left, yy + 3, Math.max(40, width - reserve), tight ? 14 : 16, tight ? 1 : 2, ink, 600))
      if (row.value && !options.bars) out.push(text(row.value, stacked ? left : x + w - 18, yy + (stacked ? 34 : 3), stacked ? 13 : 16, 650, options.negative ? coral : ink, stacked ? 'start' : 'end'))
      if (row.detail && !options.bars && step >= 38) out.push(lines(row.detail, left, yy + (stacked ? 61 : tight ? 22 : 40), width, tight ? 11 : 12, tight ? 1 : 2))
      if (options.bars && row.amount != null) out.push(`<rect x="${left}" y="${yy + 13}" width="${width - 66}" height="7" rx="4" fill="#eeeae2"/><rect x="${left}" y="${yy + 13}" width="${(width - 66) * row.amount / max}" height="7" rx="4" fill="${colors[i % colors.length]}"/>`, text(row.value, x + w - 19, yy + 19, 15, 650, coral, 'end'))
    })
  }
  const radial = (cx: number, cy: number, radius: number, sx = 1.33, sy = 1.26) => {
    const items = sheet.cuisines.slice(0, 6), points = [[-.91,-.84],[.94,-.85],[-1.18,.03],[1.17,.02],[-.92,.91],[.95,.91]]
    out.push(`<circle cx="${cx}" cy="${cy}" r="${radius + 9}" fill="#fffefa" stroke="#e5dfd4" filter="url(#paperShadow)"/>`, image(hero,cx-radius,cy-radius,radius*2,radius*2),text(prepared.heroIsIllustration ? '食物素材插画 · 非餐厅实拍' : '本人用餐照片',cx,cy+radius+28,10,400,muted,'middle'))
    items.forEach((row, i) => { const [dx,dy] = points[i], x = cx + radius * dx * sx, y = cy + radius * dy * sy; out.push(`<circle cx="${x}" cy="${y}" r="34" fill="${['#eef1e6','#fff1df','#ecf1f3'][i%3]}"/>`, image(art('cuisines', i), x-30,y-30,60,60), text(row.value,x,y+53,23,700,ink,'middle'),text(row.label,x,y+75,14,400,ink,'middle')) })

  }
  const times = (x: number, y: number, w: number, h: number) => {
    const s=find('times'); card(x,y,w,h); heading(s.title,x+20,y+38,w-40,'clock')
    if (!s.rows.length) out.push(lines(s.empty ?? '',x+22,y+112,w-44,17,3))
    else if(w<300) s.rows.slice(0,5).forEach((row,i)=>{const yy=y+83+i*25;out.push(text(row.label,x+21,yy,13),`<rect x="${x+77}" y="${yy-9}" width="70" height="6" rx="3" fill="#ede8df"/><rect x="${x+77}" y="${yy-9}" width="${70*(row.amount??0)/100}" height="6" rx="3" fill="${colors[i]}"/>`,text(row.value,x+w-19,yy,15,650,coral,'end'))})
    else s.rows.slice(0,5).forEach((row,i)=>{const xx=x+24+(i+.5)*(w-48)/Math.min(5,s.rows.length);out.push(posterIcon(row.label==='夜宵'?'moon':'sun',xx-17,y+72,34),text(row.label,xx,y+130,13,400,ink,'middle'),text(row.value,xx,y+161,20,700,coral,'middle'))})
    if(s.note)out.push(lines(s.note,x+20,y+h-23,w-40,10,2))
  }
  const conclusion = (x:number,y:number,w:number,h:number,caption='一句回顾')=>{card(x,y,w,h,'#fff8eb');out.push(tape(x+w-110,y-8));heading(caption,x+22,y+40,w-44,'bulb');out.push(lines(data.summary,x+24,y+91,w-48,22,Math.max(1,Math.floor((h-100)/32)),ink,500))}
  const periodLabel = data.periodLabel ?? data.subtitle
  if(data.type==='MONTHLY_REVIEW') {
    title('本月回顾','MONTHLY RECAP'); out.push(lines('用美食，\n记录生活里更好的每一天',38,204,235,20,3),text('统计周期',40,466,18,650),lines(periodLabel,40,500,210,16,3))
    note(sheet.cuisines[0] ? `本期常吃 · ${sheet.cuisines[0].label}\n${sheet.cuisines[0].detail}真实记录，让日常留下味道。` : '本期的食味记录，\n等待下一顿慢慢补上。',335,40,365,184,-3)
    radial(504,416,144,1.15,1.20); overview(752,30,300,559,'本月数据总览')
    ranked('frequent',24,681,335,305);ranked('new',373,681,335,305);ranked('repeat',722,681,334,305)
    ranked('people',24,1001,335,242);ranked('positive',373,1001,335,242,{max:2,photos:false});ranked('negative',722,1001,334,242,{negative:true,max:2,photos:false})
    times(24,1257,335,215);ranked('cities',373,1257,335,215,{max:3});conclusion(722,1257,334,215,'一句月度回顾')
  } else if(data.type==='ANNUAL_REVIEW') {
    title('年度回顾','TASTE MAP · YEAR IN FOOD');out.push(lines('用美食，记录生活的\n每一种热爱',38,204,235,20,3),lines(periodLabel,38,297,240,17,3))
    out.push(`<circle cx="507" cy="242" r="187" fill="#fffefa" stroke="#e7ded0" filter="url(#paperShadow)"/>`,image(hero,329,64,356,356),text(prepared.heroIsIllustration?'素材插画 · 非餐厅实拍':'这一年的真实用餐照片',505,438,11,400,muted,'middle'))
    overview(749,27,307,426,'年度总览')
    const quarters=find('quarters');card(24,477,632,291);heading('四季食味',46,514,588,'plate');quarters.rows.forEach((row,i)=>{const xx=39+i*153;out.push(`<rect x="${xx}" y="540" width="142" height="207" rx="8" fill="${['#f0f3e6','#fff6e1','#fff0e5','#edf3f8'][i]}"/>`,text(row.label,xx+12,569,19,650),image(art('quarters',i),xx+13,582,116,99),text(row.value,xx+12,710,21,650),lines(row.detail??'',xx+12,733,120,12,1))})
    // Ranked cuisines, not repeated dish names merged across restaurants.
    ranked('annual-cuisines',672,477,384,291,{max:5,bars:true,photos:false})
    ranked('frequent',24,784,251,250,{max:1,title:'年度最常回去'});ranked('rated',289,784,251,250,{max:1});ranked('cities',554,784,242,250,{max:3});ranked('people',810,784,246,250,{max:2})
    ranked('positive',24,1050,251,235,{max:2,photos:false});ranked('negative',289,1050,251,235,{max:2,photos:false,negative:true});times(554,1050,242,235);ranked('prices',810,1050,246,235,{max:4,bars:true,photos:false})
    const journey=find('journey');card(24,1301,674,171);heading(journey.title,45,1338,630);const rows=journey.rows,max=Math.max(1,...rows.map(row=>row.amount??0));rows.forEach((row,i)=>{const x=48+i*52,bar=(row.amount??0)/max*63;out.push(`<rect x="${x}" y="${1437-bar}" width="23" height="${bar}" rx="3" fill="${colors[i%colors.length]}"/>`,text(row.label,x+11,1458,11,400,muted,'middle'));if(row.amount!=null)out.push(text(String(row.amount),x+11,1430-bar,10,500,muted,'middle'))});conclusion(714,1301,342,171,'一句年终回顾')
  } else if(data.type==='RECOMMENDATION_SOURCE') {
    title('推荐来源','RECOMMENDATION SOURCES');out.push(lines('好的地方不只藏在地图里，\n也藏在真实的推荐与体验里。',38,209,235,19,4))
    note('好味道，\n在一次次真实体验里\n慢慢找到。',28,345,251,213,-3)
    card(302,56,425,532,'#fffcf4',true);out.push(tape(618,48,12),text('TASTE MAP',514,288,23,650,ink,'middle'),text('我的推荐来源',514,323,27,650,ink,'middle'),image(hero,421,344,186,172))
    const names=[...find('positive').rows,...find('negative').rows,...find('pending').rows].filter((row,i,all)=>all.findIndex(item=>item.id===row.id)===i)
    names.slice(0,4).forEach((row,i)=>{const [x,y]=[[403,148],[622,164],[374,431],[642,440]][i];out.push(`<path d="M514 310L${x} ${y}" stroke="#c7c5b9" stroke-dasharray="5 5"/><circle cx="${x}" cy="${y}" r="34" fill="${['#f5ddc5','#e3ecdf','#e8e9e3','#e5eef0'][i]}"/>`,posterIcon('people',x-24,y-24,48),lines(row.label,x-57,y+56,114,15,2,ink,500))})
    overview(753,29,303,559,'数据总览');ranked('positive',24,620,509,328,{max:5,photos:false});ranked('negative',548,620,508,328,{max:5,photos:false,negative:true})
    ranked('pending',24,964,300,293,{max:4,photos:false});ranked('source-cuisines',340,964,350,293,{max:3});ranked('source-cities',706,964,350,293,{max:3,photos:false})
    const method=find('method');card(24,1274,720,198,'#fff9ee');heading('读懂这份来源档案',45,1315,674,'bulb');method.rows.forEach((row,i)=>{out.push(text(row.label+(row.value?' · '+row.value:''),46,1359+i*61,18,650),lines(row.detail??'',46,1384+i*61,665,14,2))});out.push(lines('好的推荐，\n让生活更好吃。',783,1350,243,28,3,'#89664b',500))
  } else if(data.type==='COMPANION_ANALYSIS') {
    title('最佳饭搭子','BEST DINING COMPANION');out.push(lines('和谁一起吃饭，\n让普通的一餐，\n留下共同的回忆。',38,212,237,21,4),text('统计周期',38,419,18,650),lines(periodLabel,38,452,222,16,3))
    const partner=find('partner').rows[0];note(partner ? `${partner.label}\n${partner.value}\n仅基于你的共同用餐记录` : '共同用餐档案\n等待真实记录',341,36,378,196,-4)
    radial(516,486,167,1.05,1.26);overview(776,29,280,484,'搭子数据总览')
    ranked('frequent',24,566,294,462,{max:3,title:'一起最常去 TOP 3'});ranked('insight',790,540,266,488,{max:3,title:'共同用餐的线索',photos:false})
    const preferences=find('preferences');card(335,809,437,219);heading(preferences.title,354,848,395);preferences.rows.slice(0,6).forEach((row,i)=>{const x=356+i*65;out.push(text(row.label,x+24,893,13,500,ink,'middle'),`<rect x="${x}" y="923" width="47" height="7" rx="4" fill="#ede8de"/><rect x="${x}" y="923" width="${47*(row.amount??0)/100}" height="7" rx="4" fill="${colors[i]}"/>`,text(row.value,x+24,966,19,650,ink,'middle'))});if(!preferences.rows.length)out.push(lines(preferences.empty??'尚无口味标签',355,923,395,18,3));out.push(text('你的记录，不代替对方的口味评价',355,1008,11,400,muted))
    ranked('occasions',24,1044,340,300,{max:3,photos:false});times(380,1044,319,300);ranked('cities',715,1044,341,300,{max:4})
    conclusion(24,1361,1032,111,'留给下一顿的回忆')
  } else {
    title('那年今日','TASTE MAP · ON THIS DAY');out.push(lines('一些味道，\n让时光变得可回味。',38,213,251,20,3))
    out.push(`<g transform="rotate(-4 534 265)">`);card(333,38,375,487,'#fffefa',true);out.push(tape(468,23),image(hero,349,59,343,348,!prepared.heroIsIllustration),text('Good Food',368,447,26,500,'#89664b'),text('Better Memories',384,488,25,500,'#89664b'),'</g>')
    card(766,34,285,244,'#fff9eb',true);const dayLabel=periodLabel.match(/(\d+)\D+(\d+)/);out.push(text(dayLabel ? `${dayLabel[1]} 月 ${dayLabel[2]} 日` : periodLabel,792,137,43,700,'#775535'),text('在食物里，收藏时光的坐标。',790,213,15,400,muted));ranked('memories',24,340,297,624,{max:4,photos:true})
    const cuisines=find('cuisines');card(734,313,322,342);heading('那天记录过的食味',754,353,282);cuisines.rows.slice(0,6).forEach((row,i)=>{const x=750+(i%3)*100,y=385+Math.floor(i/3)*124;out.push(image(art('cuisines',i),x,y,88,71),text(row.value,x+44,y+91,21,650,ink,'middle'),text(row.label,x+44,y+112,13,400,ink,'middle'))});if(!cuisines.rows.length)out.push(lines('还没有可分析的菜系',758,433,271,18,3))
    note('食物会过去，\n真实记录的那一天，\n一直都在。',354,559,351,153,-2)
    ranked('cities',341,746,350,437,{max:5,photos:false});ranked('years',708,675,348,508,{max:4});ranked('remember',24,980,297,310,{max:1})
    const keywords=find('keywords');card(24,1305,647,167);heading('回忆里的食味',45,1343,603,'plate');keywords.rows.forEach((row,i)=>{const xx=45+i*120;out.push(image(art('keywords',i),xx,1368,72,58),text(row.label,xx+36,1450,15,500,ink,'middle'))});if(!keywords.rows.length)out.push(text('从下一条真实记录开始',45,1411,19,400,muted))
    conclusion(690,1200,366,272,'收藏这份回忆')
  }
  out.push(`<path d="M26 1490h1028" stroke="#e2ddd3"/>`,image(logo,28,1501,17,17),text('TASTE MAP · 记录美食，也记录自己',54,1514,11,500,muted),text(sheet.audience==='owner'?'本人完整预览 · 不直接对外分享':'仅公开记录 · 隐私处理后的分享版',1051,1514,11,400,muted,'end'),'</svg>')
  return out.join('')
}
