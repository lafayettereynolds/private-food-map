import { useRef, useState, type ChangeEvent } from 'react'
import { CheckCircle2, Database, Download, LoaderCircle, Upload } from 'lucide-react'
import { createFoodMapBackup, importFoodMapBackup } from '../db/backup'
import { ModalShell } from './ModalShell'

interface SettingsModalProps {
  restaurantCount: number
  visitCount: number
  onClose: () => void
  onImported: (message: string) => void
}

export function SettingsModal({
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

  async function exportData() {
    setExporting(true)
    setError('')
    setMessage('')
    try {
      const json = await createFoodMapBackup()
      const blob = new Blob([json], { type: 'application/json;charset=utf-8' })
      const url = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      link.download = `食途-数据备份-${new Date().toISOString().slice(0, 10)}.json`
      link.click()
      window.setTimeout(() => URL.revokeObjectURL(url), 0)
      setMessage(`已打包 ${restaurantCount} 家餐厅和 ${visitCount} 条到访记录`)
    } catch (exportError) {
      setError(exportError instanceof Error ? exportError.message : '数据导出失败。')
    } finally {
      setExporting(false)
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

  return (
    <ModalShell
      description="备份或迁移保存在当前浏览器里的私人美食记录。"
      onClose={onClose}
      size="small"
      title="数据与设置"
    >
      <div className="settings-summary"><Database size={20} /><div><strong>{restaurantCount} 家餐厅</strong><span>{visitCount} 条到访记录 · 当前浏览器</span></div></div>
      <div className="data-setting-list">
        <section>
          <div><strong>导出完整备份</strong><p>包含餐厅、评分、到访历史、照片、菜品、标签和笔记。</p></div>
          <button className="secondary-button" disabled={exporting} onClick={exportData} type="button">
            {exporting ? <LoaderCircle className="spin" size={16} /> : <Download size={16} />} 导出
          </button>
        </section>
        <section>
          <div><strong>导入食途备份</strong><p>与当前数据合并，不会清空已有餐厅和到访记录。</p></div>
          <button className="secondary-button" disabled={importing} onClick={() => fileInputRef.current?.click()} type="button">
            {importing ? <LoaderCircle className="spin" size={16} /> : <Upload size={16} />} 导入
          </button>
          <input accept="application/json,.json" className="visually-hidden" onChange={importData} ref={fileInputRef} type="file" />
        </section>
      </div>
      {message ? <p className="settings-success"><CheckCircle2 size={15} /> {message}</p> : null}
      {error ? <p className="form-error">{error}</p> : null}
      <p className="settings-privacy-note">数据不会上传到服务器。建议在重要修改后导出一份备份。</p>
    </ModalShell>
  )
}
