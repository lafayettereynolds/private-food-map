import { Download, ImagePlus, LoaderCircle, Share2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import type { AnalysisShareData } from '../types/analysisShare'
import { downloadAnalysisPoster, renderAnalysisPosterBlob, shareAnalysisPoster } from '../services/analysisPosterRenderer'
import { ModalShell } from './ModalShell'

export function AnalysisShareAction({ data }: { data: AnalysisShareData }) {
  const [open, setOpen] = useState(false)
  return (
    <>
      <button className="analysis-share-trigger" type="button" onClick={() => setOpen(true)}>
        <Share2 size={17} /> 分享分析
      </button>
      {open ? <AnalysisShareSheet data={data} onClose={() => setOpen(false)} /> : null}
    </>
  )
}

function AnalysisShareSheet({ data, onClose }: { data: AnalysisShareData; onClose: () => void }) {
  const [heroIndex, setHeroIndex] = useState(0)
  const [blob, setBlob] = useState<Blob | null>(null)
  const [previewUrl, setPreviewUrl] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    let url = ''
    setLoading(true)
    setError('')
    renderAnalysisPosterBlob(data, heroIndex).then((nextBlob) => {
      if (!active) return
      url = URL.createObjectURL(nextBlob)
      setBlob(nextBlob)
      setPreviewUrl(url)
    }).catch(() => active && setError('海报生成失败，请稍后重试。')).finally(() => active && setLoading(false))
    return () => {
      active = false
      if (url) URL.revokeObjectURL(url)
    }
  }, [data, heroIndex])

  const cycleHero = () => {
    if (data.heroCandidates.length < 2) return
    setHeroIndex((value) => (value + 1) % data.heroCandidates.length)
  }

  const sharePoster = async () => {
    if (!blob) return
    if (data.type === 'RECOMMENDATION_SOURCE' && data.metrics.some((metric) => metric.label === '最坑')) {
      window.dispatchEvent(new CustomEvent('taste-map:product-analytics', { detail: { event: 'recommendation_source_worst_share' } }))
    }
    await shareAnalysisPoster(blob, data)
  }

  return (
    <ModalShell title="分享分析" description="预览不会直接截取页面，海报会自动隐藏私人信息。" onClose={onClose} size="medium">
      <div className="analysis-share-sheet">
        <div className="analysis-poster-preview" aria-live="polite">
          {loading ? <div className="analysis-poster-loading"><LoaderCircle className="spin" size={28} />正在生成海报</div> : null}
          {!loading && error ? <div className="empty-copy">{error}</div> : null}
          {!loading && previewUrl ? <img src={previewUrl} alt={`${data.title}分享海报预览`} /> : null}
        </div>
        <div className="analysis-share-actions">
          <button type="button" onClick={cycleHero} disabled={loading || data.heroCandidates.length < 2}>
            <ImagePlus size={17} /> 换一张照片
          </button>
          <button type="button" onClick={() => blob && downloadAnalysisPoster(blob, data)} disabled={!blob || loading}>
            <Download size={17} /> 保存图片
          </button>
          <button className="primary" type="button" onClick={() => void sharePoster()} disabled={!blob || loading}>
            <Share2 size={17} /> 系统分享
          </button>
        </div>
        <p className="analysis-share-note">图片只会从这份分析对应的真实到访、餐厅封面或相关菜系候选中切换。</p>
      </div>
    </ModalShell>
  )
}
