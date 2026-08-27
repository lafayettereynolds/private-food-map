import type { CSSProperties } from 'react'
import type { AvatarPresetId, MembershipTier } from '../types/domain'
import { avatarPresetPosition } from '../utils/avatarPresets'
import { SyncedImage } from './SyncedImage'

export function PresetAvatar({ id, className = '' }: { id?: AvatarPresetId | null; className?: string }) {
  const position = avatarPresetPosition(id)
  return <span
    aria-hidden="true"
    className={`avatar-preset-sprite${className ? ` ${className}` : ''}`}
    style={{ '--avatar-x': `${position.x}%`, '--avatar-y': `${position.y}%` } as CSSProperties}
  />
}

export function UserAvatar({
  avatarImageData,
  avatarPhotoId,
  avatarPresetId,
  alt = '',
}: {
  avatarImageData: string | null
  avatarPhotoId: string | null
  avatarPresetId?: AvatarPresetId | null
  membershipTier?: MembershipTier
  alt?: string
}) {
  return <span className="user-avatar-content">
    <span className="user-avatar-clip">
      {avatarImageData || avatarPhotoId
        ? <SyncedImage alt={alt} photoId={avatarPhotoId} source={avatarImageData} />
        : <PresetAvatar id={avatarPresetId} />}
    </span>
  </span>
}
