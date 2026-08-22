async function optimizeImage(file: File, maxSide: number, quality: number): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new Error('请选择图片文件。')
  }
  if (file.size > 30 * 1024 * 1024) {
    throw new Error('原始图片不能超过 30 MB。')
  }

  const objectUrl = URL.createObjectURL(file)
  try {
    const image = new Image()
    image.src = objectUrl
    try {
      await image.decode()
    } catch {
      if (/heic|heif/i.test(`${file.type} ${file.name}`)) {
        throw new Error('当前浏览器无法处理这张 HEIC 照片，请在相册中转为 JPEG 后重试。')
      }
      throw new Error('当前浏览器无法读取这张图片，请换一张照片重试。')
    }

    const scale = Math.min(1, maxSide / Math.max(image.naturalWidth, image.naturalHeight))
    const width = Math.max(1, Math.round(image.naturalWidth * scale))
    const height = Math.max(1, Math.round(image.naturalHeight * scale))
    const canvas = document.createElement('canvas')
    canvas.width = width
    canvas.height = height
    const context = canvas.getContext('2d')
    if (!context) throw new Error('当前浏览器无法处理这张图片。')
    context.drawImage(image, 0, 0, width, height)
    const webp = canvas.toDataURL('image/webp', quality)
    return webp.startsWith('data:image/webp') ? webp : canvas.toDataURL('image/jpeg', quality)
  } finally {
    URL.revokeObjectURL(objectUrl)
  }
}

export function optimizeMarkerImage(file: File): Promise<string> {
  return optimizeImage(file, 1024, 0.82)
}

export function optimizeAvatarImage(file: File): Promise<string> {
  return optimizeImage(file, 256, 0.76)
}

export function optimizeVisitPhoto(file: File): Promise<string> {
  return optimizeImage(file, 1920, 0.8)
}
