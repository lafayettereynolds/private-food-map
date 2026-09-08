import { useEffect, useRef, useState, type ChangeEvent } from 'react'
import { AlertTriangle, CheckCircle2, Cloud, CloudUpload, Database, Download, LoaderCircle, RefreshCw, Sparkles, Trash2, Upload } from 'lucide-react'
import { downloadFoodMapBackup, importFoodMapBackup } from '../db/backup'
import { ModalShell } from './ModalShell'
import { CLOUD_SYNC_ENABLED, DATABASE_NAME, ENVIRONMENT_LABEL } from '../config/appEnvironment'
import { dismissInitialMigration, syncNow } from '../services/cloudSync'
import { useCloudSync } from '../services/useCloudSync'
import { clearLocalPhotoCache, getLocalPhotoCacheBytes } from '../services/photoAssets'
import type { MembershipTier } from '../types/domain'
import { openPremiumPaywall } from '../services/premiumPaywall'

interface SettingsModalProps {
  membershipTier: MembershipTier
  restaurantCount: number
  visitCount: number
  onClose: () => void
  onImported: (message: string) => void
  section?: 'all' | 'sync' | 'storage' | 'export' | 'import'
}

export function SettingsModal({
  membershipTier,
  restaurantCount,
  visitCount,
  onClose,
  onImported,
  section = 'all',
}: SettingsModalProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [exporting, setExporting] = useState(false)
  const [importing, setImporting] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const syncState = useCloudSync()
  const [cacheBytes, setCacheBytes] = useState(0)

  useEffect(() => {
    void getLocalPhotoCacheBytes().then(setCacheBytes)
  }, [])

  async function exportData() {
    setExporting(true)
    setError('')
    setMessage('')
    try {
      await downloadFoodMapBackup()
      setMessage(`已打包 ${restaurantCount} 家餐厅和 ${visitCount} 条到访记录`)
    } catch (exportError) {
      setError(exportError instanceof Error ? exportError.message : '数据导出失败。')
    } finally {
      setExporting(false)
    }
  }

  async function syncData() {
    setError('')
    setMessage('')
    try {
      const result = await syncNow()
      if (result.migrationRequired) {
        setMessage('检测到本地已有数据，请先确认是否迁移到云端。')
        return
      }
      setMessage(`同步完成：云端 ${result.cloudCounts.restaurants} 家餐厅、${result.cloudCounts.visits} 条到访记录`)
    } catch (syncError) {
      setError(syncError instanceof Error ? syncError.message : '云端同步失败。')
    }
  }

  async function migrateToCloud() {
    setError('')
    setMessage('')
    try {
      await downloadFoodMapBackup()
      const result = await syncNow({ allowInitialUpload: true })
      if (
        result.localCounts.restaurants !== result.cloudCounts.restaurants ||
        result.localCounts.visits !== result.cloudCounts.visits
      ) {
        throw new Error('云端数量校验没有通过，本地备份已下载，数据没有被删除。')
      }
      setMessage(`云端迁移完成：${result.cloudCounts.restaurants} 家餐厅、${result.cloudCounts.visits} 条到访记录`)
    } catch (migrationError) {
      setError(migrationError instanceof Error ? migrationError.message : '云端迁移失败。')
    }
  }

  async function importData(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setImporting(true)
    setError('')
    setMessage('')
    try {
      const result = await importFoodMapBackup(await file.text())
      const successMessage = `已合并 ${result.restaurantCount} 家餐厅和 ${result.visitCount} 条到访记录`
      setMessage(successMessage)
      onImported(successMessage)
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : '数据导入失败。')
    } finally {
      setImporting(false)
    }
  }

  async function clearPhotoCache() {
    await clearLocalPhotoCache()
    setCacheBytes(0)
    setMessage('可重新生成的本地图片缓存已清除；业务数据和用户保存的原图没有删除。')
  }

  return (
    <ModalShell
      description="管理保存在当前浏览器里的私人美食记录。"
      onClose={onClose}
      size="small"
      title={{ all: '数据与设置', sync: '同步', storage: '存储', export: '导出备份', import: '导入数据' }[section]}
    >
      {section === 'all' ? <button className="settings-membership-entry" onClick={() => openPremiumPaywall('settings_entry')} type="button">
        <span><Sparkles size={18} /></span>
        <div><strong>会员与订阅</strong><small>{membershipTier === 'member' ? '查看当前方案、权益与恢复购买' : '查看功能对比与订阅方案'}</small></div>
        <b>{membershipTier === 'member' ? '已开通' : '查看'}</b>
      </button> : null}
      <div className="settings-summary"><Database size={20} /><div><strong>{restaurantCount} 家餐厅</strong><span>{visitCount} 条到访记录 · {ENVIRONMENT_LABEL} · {DATABASE_NAME}</span></div></div>
      {CLOUD_SYNC_ENABLED && (section === 'all' || section === 'sync') && syncState.status === 'migrationRequired' ? (
        <div className="cloud-migration-notice">
          <AlertTriangle size={19} />
          <div>
            <strong>检测到本地已有数据</strong>
            <p>本地：{syncState.localCounts?.restaurants ?? restaurantCount} 家餐厅、{syncState.localCounts?.visits ?? visitCount} 条到访记录</p>
            <p>云端：{syncState.cloudCounts?.restaurants ?? 0} 家餐厅、{syncState.cloudCounts?.visits ?? 0} 条到访记录</p>
            <span>上传前会先自动下载完整 JSON 备份，空云端不会覆盖本地数据。</span>
            <div className="cloud-migration-actions">
              <button className="primary-button" onClick={() => void migrateToCloud()} type="button"><CloudUpload size={15} /> 上传到云端</button>
              <button className="text-button" onClick={dismissInitialMigration} type="button">暂不处理</button>
            </div>
          </div>
        </div>
      ) : null}
      <div className="data-setting-list">
        {section === 'all' || section === 'sync' ? <section>
          <div><strong>云端同步</strong><p>{CLOUD_SYNC_ENABLED ? `通过 Cloudflare D1 同步餐厅、到访、评分、笔记和照片索引。${syncState.lastSuccessfulSyncAt ? ` 上次成功：${new Date(syncState.lastSuccessfulSyncAt).toLocaleString('zh-CN')}` : ''}` : '当前本地测试或预览环境不会连接正式 D1。'}</p></div>
          {CLOUD_SYNC_ENABLED ? <button className="secondary-button" disabled={syncState.status === 'syncing'} onClick={() => void syncData()} type="button">{syncState.status === 'syncing' ? <LoaderCircle className="spin" size={16} /> : <RefreshCw size={16} />} 立即同步</button> : <span className="local-only-chip"><Cloud size={14} /> 仅本地</span>}
        </section> : null}
        {section === 'all' || section === 'storage' ? <section>
          <div><strong>本地图片缓存</strong><p>{formatStorageSize(cacheBytes)} · 只清理可重新生成的缓存，不删除业务数据或用户保存的唯一原图。</p></div>
          <button className="secondary-button" disabled={!cacheBytes} onClick={() => void clearPhotoCache()} type="button"><Trash2 size={15} /> 清除缓存</button>
        </section> : null}
        {section === 'all' || section === 'export' ? <section>
          <div><strong>导出完整备份</strong><p>包含餐厅、评分、到访历史、菜品、笔记和照片 metadata；Backup v1 不包含照片原图。</p></div>
          <button className="secondary-button" disabled={exporting} onClick={exportData} type="button">
            {exporting ? <LoaderCircle className="spin" size={16} /> : <Download size={16} />} 导出
          </button>
        </section> : null}
        {section === 'all' || section === 'import' ? <section>
          <div><strong>导入 Taste Map 备份</strong><p>与当前数据合并，不会清空已有餐厅和到访记录。</p></div>
          <button className="secondary-button" disabled={importing} onClick={() => fileInputRef.current?.click()} type="button">
            {importing ? <LoaderCircle className="spin" size={16} /> : <Upload size={16} />} 导入
          </button>
          <input accept="application/json,.json" className="visually-hidden" onChange={importData} ref={fileInputRef} type="file" />
        </section> : null}
      </div>
      {message ? <p className="settings-success"><CheckCircle2 size={15} /> {message}</p> : null}
      {error ? <p className="form-error">{error}</p> : null}
      <p className="settings-privacy-note">照片原图不进入 Backup v1；清理本地缓存不会删除业务数据、用户保存的备份或唯一原图。测试环境与正式环境仍然隔离。</p>
    </ModalShell>
  )
}

function formatStorageSize(bytes: number) {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(bytes >= 100 * 1024 * 1024 ? 0 : 1)} MB`
}
