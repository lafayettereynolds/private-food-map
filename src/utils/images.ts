async function optimizeImage(file: File, maxSide: number, quality: number): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new Error('请选择图片文件。')
  }
  if (file.size > 10 * 1024 * 1024) {
    throw new Error('图片不能超过 10 MB。')
  }

  const objectUrl = URL.createObjectURL(file)
  try {
    const image = new Image()
    image.src = objectUrl
    await image.decode()

    const scale = Math.min(1, maxSide / Math.max(image.naturalWidth, image.naturalHeight))
    const width = Math.max(1, Math.round(image.naturalWidth * scale))
    const height = Math.max(1, Math.round(image.naturalHeight * scale))
    const canvas = document.createElement('canvas')
    canvas.width = width
    canvas.height = height
    const context = canvas.getContext('2d')
    if (!context) throw new Error('当前浏览器无法处理这张图片。')
    context.drawImage(image, 0, 0, width, height)
    return canvas.toDataURL('image/webp', quality)
  } finally {
    URL.revokeObjectURL(objectUrl)
  }
}

export function optimizeMarkerImage(file: File): Promise<string> {
  return optimizeImage(file, 512, 0.82)
}

export function optimizeVisitPhoto(file: File): Promise<string> {
  return optimizeImage(file, 960, 0.8)
}
