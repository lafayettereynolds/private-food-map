import type { ReactNode } from 'react'
import { ChevronRight, LocateFixed, Search, Share2, Store } from 'lucide-react'
import './tasteMapRestaurantAcquisitionShared.css'

interface TasteMapRestaurantAcquisitionScaffoldProps {
  pageHeader?: boolean
  search: ReactNode
  nearby: ReactNode
  onOpenShare: () => void
  onOpenManual: () => void
  sharePanel?: ReactNode
}

/**
 * Canonical Add Restaurant product skeleton shared by formal Web and Hybrid.
 * Adapters provide data/capability behavior; they do not redraw the hierarchy.
 */
export function TasteMapRestaurantAcquisitionScaffold({
  pageHeader = false,
  search,
  nearby,
  onOpenShare,
  onOpenManual,
  sharePanel,
}: TasteMapRestaurantAcquisitionScaffoldProps) {
  return <div className="tm-acquisition" data-product-contract="restaurant-acquisition">
    {pageHeader ? <header className="tm-acquisition__page-header">
      <h1>添加餐厅</h1>
      <p>搜索、附近、外部分享或手动添加</p>
    </header> : null}
    <section className="tm-acquisition__section" data-acquisition-capability="search">
      <header><Search aria-hidden="true" size={18} /><span><strong>搜索餐厅</strong><small>名称、地址与城市范围</small></span></header>
      {search}
    </section>
    <section className="tm-acquisition__section" data-acquisition-capability="nearby">
      <header><LocateFixed aria-hidden="true" size={18} /><span><strong>附近餐厅</strong><small>当前位置 3 公里内，按实际距离排序</small></span></header>
      {nearby}
    </section>
    <div className="tm-acquisition__secondary-actions">
      <button aria-label="从外部分享添加" data-acquisition-capability="share" onClick={onOpenShare} type="button">
        <Share2 aria-hidden="true" size={18} /><span><strong>从外部分享添加</strong><small>Apple 地图、高德地图、网页 URL 或分享文字</small></span><ChevronRight aria-hidden="true" size={17} />
      </button>
      {sharePanel}
      <button aria-label="手动添加餐厅" data-acquisition-capability="manual" onClick={onOpenManual} type="button">
        <Store aria-hidden="true" size={18} /><span><strong>手动添加餐厅</strong><small>适合地图上搜不到的小摊、快闪店、私房店和新开门店</small></span><ChevronRight aria-hidden="true" size={17} />
      </button>
    </div>
  </div>
}
