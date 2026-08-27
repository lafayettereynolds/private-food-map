import { useEffect, useRef, useState, type ChangeEvent } from 'react'
import { AlertTriangle, CheckCircle2, Cloud, CloudUpload, Database, Download, HardDrive, Image, LoaderCircle, LogOut, RefreshCw, Sparkles, Trash2, Upload } from 'lucide-react'
import { downloadFoodMapBackup, importFoodMapBackup } from '../db/backup'
import { ModalShell } from './ModalShell'
import { CLOUD_SYNC_ENABLED, DATABASE_NAME, ENVIRONMENT_LABEL } from '../config/appEnvironment'
import { dismissInitialMigration, syncNow } from '../services/cloudSync'
import { useCloudSync } from '../services/useCloudSync'
import { connectGoogleDrive, disconnectGoogleDrive } from '../services/googleDrive'
import { useGoogleDrive } from '../services/useGoogleDrive'
import { enablePhotoAutoSync, getGoogleDriveAccountWarning, refreshPendingPhotoCount, syncPendingPhotos } from '../services/photoSync'
import { usePhotoSync } from '../services/usePhotoSync'
import { clearLocalPhotoCache, getLocalPhotoCacheBytes } from '../services/photoAssets'
import type { MembershipTier } from '../types/domain'
import { openPremiumPaywall } from '../services/premiumPaywall'

interface SettingsModalProps {
  membershipTier: MembershipTier
  restaurantCount: number
  visitCount: number
  onClose: () => void
  onImported: (message: string) => void
}

export function SettingsModal({
  membershipTier,
  restaurantCount,
  visitCount,
  onClose,
  onImported,
}: SettingsModalProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [exporting, setExporting] = useState(false)
  const [importing, setImporting] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const syncState = useCloudSync()
  const googleDrive = useGoogleDrive()
  const photoSync = usePhotoSync()
  const [cacheBytes, setCacheBytes] = useState(0)
  const [accountWarning, setAccountWarning] = useState<string | null>(null)

  useEffect(() => {
    void Promise.all([getLocalPhotoCacheBytes(), getGoogleDriveAccountWarning(), refreshPendingPhotoCount()])
      .then(([bytes, warning]) => {
        setCacheBytes(bytes)
        setAccountWarning(warning)
      })
  }, [googleDrive.status, googleDrive.accountId, photoSync.completed])

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

  async function connectDrive() {
    setError('')
    setMessage('')
    try {
      const connected = await connectGoogleDrive()
      const pending = await refreshPendingPhotoCount()
      if (!pending) enablePhotoAutoSync()
      const warning = await getGoogleDriveAccountWarning()
      setAccountWarning(warning)
      setMessage(warning ?? `Google Drive 已连接：${connected.email ?? ''}`)
    } catch (connectError) {
      setError(connectError instanceof Error ? connectError.message : 'Google Drive 连接失败。')
    }
  }

  async function syncPhotos() {
    setError('')
    setMessage('')
    try {
      const result = await syncPendingPhotos()
      await syncNow().catch(() => undefined)
      setCacheBytes(await getLocalPhotoCacheBytes())
      setMessage(result.failed
        ? `${result.completed} 张成功，${result.failed} 张失败；失败原图仍保存在本机。`
        : result.total ? `${result.completed} 张图片已同步到 Google Drive。` : '本地图片已经全部同步。')
    } catch (photoError) {
      setError(photoError instanceof Error ? photoError.message : '图片同步失败。')
    }
  }

  async function clearPhotoCache() {
    await clearLocalPhotoCache()
    setCacheBytes(0)
    setMessage('本地图片缓存已清除，Google Drive 原图没有删除。')
  }

  return (
    <ModalShell
      description="备份或迁移保存在当前浏览器里的私人美食记录。"
      onClose={onClose}
      size="small"
      title="数据与设置"
    >
      <button className="settings-membership-entry" onClick={() => openPremiumPaywall('settings_entry')} type="button">
        <span><Sparkles size={18} /></span>
        <div><strong>会员与订阅</strong><small>{membershipTier === 'member' ? '查看当前方案、权益与恢复购买' : '查看功能对比与订阅方案'}</small></div>
        <b>{membershipTier === 'member' ? '已开通' : '查看'}</b>
      </button>
      <div className="settings-summary"><Database size={20} /><div><strong>{restaurantCount} 家餐厅</strong><span>{visitCount} 条到访记录 · {ENVIRONMENT_LABEL} · {DATABASE_NAME}</span></div></div>
      {CLOUD_SYNC_ENABLED && syncState.status === 'migrationRequired' ? (
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
        <section>
          <div><strong>云端同步</strong><p>{CLOUD_SYNC_ENABLED ? `通过 Cloudflare D1 同步餐厅、到访、评分、笔记和照片索引。${syncState.lastSuccessfulSyncAt ? ` 上次成功：${new Date(syncState.lastSuccessfulSyncAt).toLocaleString('zh-CN')}` : ''}` : '当前本地测试或预览环境不会连接正式 D1。'}</p></div>
          {CLOUD_SYNC_ENABLED ? <button className="secondary-button" disabled={syncState.status === 'syncing'} onClick={() => void syncData()} type="button">{syncState.status === 'syncing' ? <LoaderCircle className="spin" size={16} /> : <RefreshCw size={16} />} 立即同步</button> : <span className="local-only-chip"><Cloud size={14} /> 仅本地</span>}
        </section>
        <section className="google-drive-setting">
          <div>
            <strong><Image size={15} /> 图片存储</strong>
            <p>{googleDrive.status === 'connected' ? `Google Drive 已连接 · ${googleDrive.email}` : '连接你自己的 Google Drive，照片保持私密并可跨设备读取。'}</p>
            {accountWarning ? <span className="drive-account-warning"><AlertTriangle size={13} /> {accountWarning}</span> : null}
            {photoSync.pending ? <span className="photo-pending-note">待同步 {photoSync.pending} 张{photoSync.status === 'syncing' ? ` · ${photoSync.completed} / ${photoSync.total}` : ''}</span> : null}
          </div>
          {googleDrive.status === 'connected' ? (
            <div className="setting-button-group">
              <button className="secondary-button" disabled={photoSync.status === 'syncing' || Boolean(accountWarning)} onClick={() => void syncPhotos()} type="button">{photoSync.status === 'syncing' ? <LoaderCircle className="spin" size={16} /> : <CloudUpload size={16} />} {photoSync.pending ? '同步图片' : '检查图片'}</button>
              <button className="plain-icon-button" aria-label="断开 Google Drive" onClick={disconnectGoogleDrive} title="断开 Google Drive" type="button"><LogOut size={15} /></button>
            </div>
          ) : (
            <button className="secondary-button" disabled={googleDrive.status === 'connecting'} onClick={() => void connectDrive()} type="button">{googleDrive.status === 'connecting' ? <LoaderCircle className="spin" size={16} /> : <HardDrive size={16} />} 连接 Google Drive</button>
          )}
        </section>
        <section>
          <div><strong>本地图片缓存</strong><p>{formatStorageSize(cacheBytes)} · 清除后会在需要时从你的 Google Drive 重新加载。</p></div>
          <button className="secondary-button" disabled={!cacheBytes} onClick={() => void clearPhotoCache()} type="button"><Trash2 size={15} /> 清除缓存</button>
        </section>
        <section>
          <div><strong>导出完整备份</strong><p>包含餐厅、评分、到访历史、菜品、笔记和 Drive 图片索引；不包含 Drive 图片二进制。</p></div>
          <button className="secondary-button" disabled={exporting} onClick={exportData} type="button">
            {exporting ? <LoaderCircle className="spin" size={16} /> : <Download size={16} />} 导出
          </button>
        </section>
        <section>
          <div><strong>导入 Taste Map 备份</strong><p>与当前数据合并，不会清空已有餐厅和到访记录。</p></div>
          <button className="secondary-button" disabled={importing} onClick={() => fileInputRef.current?.click()} type="button">
            {importing ? <LoaderCircle className="spin" size={16} /> : <Upload size={16} />} 导入
          </button>
          <input accept="application/json,.json" className="visually-hidden" onChange={importData} ref={fileInputRef} type="file" />
        </section>
      </div>
      {message ? <p className="settings-success"><CheckCircle2 size={15} /> {message}</p> : null}
      {error ? <p className="form-error">{error}</p> : null}
      <p className="settings-privacy-note">实际照片只保存在你授权的私有 Google Drive；D1 仅保存图片索引，不保存图片、OAuth 令牌或密钥。测试环境与正式环境仍然隔离。</p>
    </ModalShell>
  )
}

function formatStorageSize(bytes: number) {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / 1024 / 1024).toFixed(bytes >= 100 * 1024 * 1024 ? 0 : 1)} MB`
}
