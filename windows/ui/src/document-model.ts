import type { ViewMode } from './editor'

export interface SearchResult {
  page: number
  count: number
  snippet: string
}

export interface PageHistory {
  history: number[]
  historyIndex: number
}

export function pagesForMode(mode: ViewMode, current: number, count: number): number[] {
  if (mode === 'continuous' || mode === 'grid') return Array.from({ length: count }, (_, index) => index + 1)
  if (mode === 'single') return [current]
  if (mode === 'book') {
    if (current === 1) return [1]
    const start = current % 2 === 0 ? current : current - 1
    return [start, start + 1].filter((page) => page <= count)
  }
  const start = current % 2 === 1 ? current : current - 1
  return [start, start + 1].filter((page) => page >= 1 && page <= count)
}

export function searchDocument(pageText: string[], query: string): SearchResult[] {
  const needle = query.trim().toLocaleLowerCase()
  if (!needle) return []
  return pageText.flatMap((text, index) => {
    const lower = text.toLocaleLowerCase()
    let cursor = 0
    let count = 0
    while ((cursor = lower.indexOf(needle, cursor)) >= 0) {
      count++
      cursor += Math.max(1, needle.length)
    }
    if (count === 0) return []
    const first = lower.indexOf(needle)
    return [{ page: index + 1, count, snippet: text.slice(Math.max(0, first - 50), first + needle.length + 90) }]
  })
}

export function pushPageHistory(current: PageHistory, page: number): PageHistory {
  const history = current.history.slice(0, current.historyIndex + 1)
  if (history[history.length - 1] === page) return current
  history.push(page)
  return { history, historyIndex: history.length - 1 }
}

export function movePageHistory(current: PageHistory, direction: -1 | 1): PageHistory & { page?: number } {
  const historyIndex = current.historyIndex + direction
  if (historyIndex < 0 || historyIndex >= current.history.length) return current
  return { ...current, historyIndex, page: current.history[historyIndex] }
}
