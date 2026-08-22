import type { AvatarPresetId } from '../types/domain'

export const AVATAR_PRESETS: ReadonlyArray<{ id: AvatarPresetId; label: string; column: number; row: number }> = [
  { id: 'polar-bear', label: '北极熊', column: 0, row: 0 },
  { id: 'penguin', label: '企鹅', column: 1, row: 0 },
  { id: 'cat', label: '猫咪', column: 2, row: 0 },
  { id: 'dog', label: '小狗', column: 3, row: 0 },
  { id: 'parrot', label: '鹦鹉', column: 0, row: 1 },
  { id: 'dinosaur', label: '小恐龙', column: 1, row: 1 },
  { id: 'shiba', label: '柴犬', column: 2, row: 1 },
  { id: 'panda', label: '熊猫', column: 3, row: 1 },
  { id: 'otter', label: '水獭', column: 0, row: 2 },
  { id: 'hedgehog', label: '刺猬', column: 1, row: 2 },
  { id: 'rabbit', label: '兔子', column: 2, row: 2 },
  { id: 'koala', label: '考拉', column: 3, row: 2 },
  { id: 'fox', label: '狐狸', column: 0, row: 3 },
  { id: 'raccoon', label: '浣熊', column: 1, row: 3 },
  { id: 'deer', label: '小鹿', column: 2, row: 3 },
  { id: 'whale', label: '鲸鱼', column: 3, row: 3 },
]

export function avatarPresetPosition(id: AvatarPresetId | null | undefined) {
  const preset = AVATAR_PRESETS.find((item) => item.id === id) ?? AVATAR_PRESETS[0]
  return { x: preset.column * 100 / 3, y: preset.row * 100 / 3 }
}
