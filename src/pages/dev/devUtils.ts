export const money = (value: number | null | undefined) =>
  Number(value || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })

export const dateTime = (value: string | null | undefined) =>
  value ? new Date(value).toLocaleString('pt-BR') : '—'

export const dateOnly = (value: string | null | undefined) =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—'

export function downloadCsv(filename: string, rows: Record<string, unknown>[]) {
  if (!rows.length) return
  const keys = Array.from(new Set(rows.flatMap((row) => Object.keys(row))))
  const escape = (value: unknown) => {
    const raw = value == null ? '' : typeof value === 'object' ? JSON.stringify(value) : String(value)
    return `"${raw.replace(/"/g, '""')}"`
  }
  const csv = [keys.map(escape).join(';'), ...rows.map((row) => keys.map((key) => escape(row[key])).join(';'))].join('\n')
  const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}

export function copyText(value: string) {
  return navigator.clipboard?.writeText(value)
}

export function hoursSince(value: string) {
  return Math.max(0, (Date.now() - new Date(value).getTime()) / 3_600_000)
}

export function jsonText(value: unknown) {
  try { return JSON.stringify(value ?? {}, null, 2) } catch { return '{}' }
}
