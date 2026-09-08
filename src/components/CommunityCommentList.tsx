import type { TasteMapCommunityCommentDTO } from '../platform/TasteMapPlatform'

/** Shared remote comment states: a failed read is never an empty conversation. */
export function CommunityCommentList({ items, loading, error, onRetry }: {
  items: TasteMapCommunityCommentDTO[]
  loading: boolean
  error: string | null
  onRetry: () => void
}) {
  return <div className="community-comment-list" aria-busy={loading}>
    {loading ? <p className="community-comment-empty" role="status">正在加载评论…</p>
      : error ? <div role="alert">
          <p className="community-comment-empty">{error}</p>
          <button className="tm-hybrid-page-action" onClick={onRetry} type="button">重试加载评论</button>
        </div>
      : items.length ? items.map((comment) => <p key={comment.id}><strong>{comment.author.name}</strong><span>{comment.body}</span></p>)
      : <p className="community-comment-empty">还没有评论，来说说你的想法。</p>}
  </div>
}
