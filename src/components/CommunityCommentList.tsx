import type { TasteMapCommunityCommentDTO } from '../platform/TasteMapPlatform'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'
import { UGCSafetyMenu } from './UGCSafetyMenu'
import { useUGCSafetyState } from './ugcSafetyState'

/** Shared remote comment states: a failed read is never an empty conversation. */
export function CommunityCommentList({ items, loading, error, onRetry, platform }: {
  items: TasteMapCommunityCommentDTO[]
  loading: boolean
  error: string | null
  onRetry: () => void
  platform?: TasteMapPlatform
}) {
  return <div className="community-comment-list" aria-busy={loading}>
    {loading ? <p className="community-comment-empty" role="status">正在加载评论…</p>
      : error ? <div role="alert">
          <p className="community-comment-empty">{error}</p>
          <button className="tm-hybrid-page-action" onClick={onRetry} type="button">重试加载评论</button>
        </div>
      : items.length ? items.map((comment) => <CommentRow key={comment.id} comment={comment} platform={platform} />)
      : <p className="community-comment-empty">还没有评论，来说说你的想法。</p>}
  </div>
}

function CommentRow({ comment, platform }: { comment: TasteMapCommunityCommentDTO; platform?: TasteMapPlatform }) {
  return platform ? <ModeratedCommentRow comment={comment} platform={platform} /> : <p><strong>{comment.author.name}</strong><span>{comment.body}</span></p>
}
function ModeratedCommentRow({ comment, platform }: { comment: TasteMapCommunityCommentDTO; platform: TasteMapPlatform }) {
  const safety = useUGCSafetyState(platform)
  if (safety.blocked.has(comment.author.id)) return null
  return <div className="community-comment-row">
    {safety.deleted.has(comment.id) ? <p role="status">评论已隐藏</p> : <p><strong>{comment.author.name}</strong><span>{comment.body}</span></p>}
    <UGCSafetyMenu platform={platform} target={{ type: 'comment', id: comment.id }} />
  </div>
}
