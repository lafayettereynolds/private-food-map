export function currentDateAndTime() {
  return dateAndTimeFromIso(new Date().toISOString())
}

export function dateAndTimeFromIso(value: string) {
  const date = new Date(value)
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
  return {
    date: local.toISOString().slice(0, 10),
    time: local.toISOString().slice(11, 16),
  }
}

export function localDateTimeToIso(date: string, time: string) {
  return new Date(`${date}T${time || '12:00'}:00`).toISOString()
}

export function formatVisitDateTime(value: string | null) {
  if (!value) return '尚未到访'
  return new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}
