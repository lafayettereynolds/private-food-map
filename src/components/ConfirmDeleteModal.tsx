import { LoaderCircle, Trash2, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { ModalShell } from './ModalShell'

interface ConfirmDeleteModalProps {
  restaurantName: string
  visitCount?: number
  onCancel: () => void
  onConfirm: () => Promise<void>
}

export function ConfirmDeleteModal({
  restaurantName,
  visitCount = 0,
  onCancel,
  onConfirm,
}: ConfirmDeleteModalProps) {
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState('')

  async function handleConfirm() {
    setDeleting(true)
    setError('')
    try {
      await onConfirm()
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : '删除失败，请稍后重试。')
      setDeleting(false)
    }
  }

  return (
    <ModalShell title="删除这家餐厅？" onClose={onCancel} size="small">
      <div className="delete-warning">
        <span><TriangleAlert size={21} /></span>
        <p><strong>{restaurantName}</strong> 将从你的私人地图中删除。{visitCount > 0 ? `同时会删除 ${visitCount} 条到访记录。` : ''}此操作无法撤销。</p>
      </div>
      {error ? <p className="form-error">{error}</p> : null}
      <footer className="modal-actions">
        <button className="secondary-button" onClick={onCancel} type="button">取消</button>
        <button className="danger-button" disabled={deleting} onClick={handleConfirm} type="button">
          {deleting ? <LoaderCircle className="spin" size={16} /> : <Trash2 size={16} />} 确认删除
        </button>
      </footer>
    </ModalShell>
  )
}
