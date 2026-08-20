import { AlertCircle, Check, Cloud, LoaderCircle, UploadCloud } from 'lucide-react'
import type { CloudSyncState } from '../types/cloudSync'
import { syncNow } from '../services/cloudSync'

interface CloudSyncIndicatorProps {
  state: CloudSyncState
  onOpenSettings: () => void
}

export function CloudSyncIndicator({ state, onOpenSettings }: CloudSyncIndicatorProps) {
  if (state.status === 'disabled') return null

  const meta = {
    idle: { label: '等待同步', icon: <Cloud size={14} /> },
    syncing: { label: '正在同步…', icon: <LoaderCircle className="spin" size={14} /> },
    synced: { label: '已同步', icon: <Check size={14} /> },
    error: { label: '同步失败', icon: <AlertCircle size={14} /> },
    migrationRequired: { label: '待迁移', icon: <UploadCloud size={14} /> },
  }[state.status]

  function handleClick() {
    if (state.status === 'error') {
      void syncNow().catch(() => undefined)
      return
    }
    onOpenSettings()
  }

  return (
    <button
      className={`cloud-sync-indicator is-${state.status}`}
      onClick={handleClick}
      title={state.status === 'error' ? '点击重试云端同步' : '打开云端同步设置'}
      type="button"
    >
      {meta.icon}<span>{meta.label}</span>
    </button>
  )
}
