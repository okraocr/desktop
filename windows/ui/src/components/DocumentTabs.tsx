interface TabDocument {
  id: string
  fileName: string
  dirty: boolean
}

interface Props {
  documents: TabDocument[]
  activeId: string | null
  splitId: string | null
  onActivate: (id: string) => void
  onClose: (id: string) => void
  onOpen: () => void
  onSplitChange: (id: string | null) => void
}

export function DocumentTabs({ documents, activeId, splitId, onActivate, onClose, onOpen, onSplitChange }: Props) {
  const compareOptions = documents.filter((document) => document.id !== activeId)
  return (
    <div className="flex h-10 shrink-0 items-end gap-1 border-b border-neutral-300 bg-neutral-100 px-2 pt-1">
      <div role="tablist" aria-label="Open PDFs" className="thin-scroll flex min-w-0 flex-1 gap-1 overflow-x-auto">
        {documents.map((document) => (
          <div
            key={document.id}
            className={`group flex max-w-56 shrink-0 items-center gap-2 rounded-t-md border px-3 py-1.5 text-xs ${
              document.id === activeId
                ? 'border-neutral-300 border-b-white bg-white text-neutral-900'
                : 'border-transparent bg-neutral-200 text-neutral-600 hover:bg-neutral-50'
            }`}
          >
            <button
              role="tab"
              aria-selected={document.id === activeId}
              onClick={() => onActivate(document.id)}
              className="flex min-w-0 items-center gap-2"
              title={document.fileName}
            >
              <span className="truncate">{document.fileName}</span>
              {document.dirty && <span className="text-amber-600" title="Unsaved edits">●</span>}
            </button>
            <button
              type="button"
              aria-label={`Close ${document.fileName}`}
              onClick={() => onClose(document.id)}
              className="rounded px-1 text-neutral-400 hover:bg-neutral-200 hover:text-neutral-800"
            >
              ×
            </button>
          </div>
        ))}
      </div>
      <button
        onClick={onOpen}
        className="mb-1 rounded border border-neutral-300 bg-white px-2 py-1 text-xs text-brand-700 hover:bg-brand-50"
      >
        + Open
      </button>
      <label className="mb-1 flex items-center gap-1 text-xs text-neutral-500">
        Compare
        <select
          value={splitId ?? ''}
          disabled={compareOptions.length === 0}
          onChange={(event) => onSplitChange(event.target.value || null)}
          className="max-w-40 rounded border border-neutral-300 bg-white px-1.5 py-1 text-xs text-neutral-700"
        >
          <option value="">Off</option>
          {compareOptions.map((document) => (
            <option key={document.id} value={document.id}>{document.fileName}</option>
          ))}
        </select>
      </label>
    </div>
  )
}
