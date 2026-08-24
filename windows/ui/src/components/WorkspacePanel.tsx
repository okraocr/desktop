import type { CurrentDocument, Run } from '../types'

interface Props {
  doc: CurrentDocument | null
  runs: Run[]
  activeRunId: string | null
  parsing: boolean
  onViewRun: (run: Run) => void
  onResumeRun: (run: Run) => void
  onRevealDocument: () => void
}

const STATUS_STYLE: Record<string, string> = {
  running: 'bg-sky-500',
  succeeded: 'bg-brand-600',
  failed: 'bg-red-500',
  canceled: 'bg-amber-500',
  interrupted: 'bg-amber-500',
}

const RESUMABLE = new Set(['canceled', 'failed', 'interrupted'])

function formatTime(iso: string): string {
  const date = new Date(iso)
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export function WorkspacePanel({
  doc,
  runs,
  activeRunId,
  parsing,
  onViewRun,
  onResumeRun,
  onRevealDocument,
}: Props) {
  return (
    <aside className="flex w-64 shrink-0 flex-col border-r border-neutral-200 bg-neutral-50">
      <div className="border-b border-neutral-200 px-3 py-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Document</div>
        {doc ? (
          <div className="mt-1">
            <div className="truncate text-sm font-medium text-neutral-800" title={doc.path}>
              {doc.fileName}
            </div>
            <div className="text-xs text-neutral-500">{doc.pageCount} pages · stays in place</div>
            <button
              className="mt-1 text-xs text-brand-700 hover:underline"
              onClick={onRevealDocument}
            >
              Reveal in Explorer
            </button>
          </div>
        ) : (
          <div className="mt-1 text-xs text-neutral-500">No document open.</div>
        )}
      </div>
      <div className="flex min-h-0 flex-1 flex-col px-3 py-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Run history</div>
        <div className="thin-scroll mt-1 min-h-0 flex-1 overflow-y-auto">
          {runs.length === 0 && (
            <div className="mt-2 text-xs text-neutral-500">
              No runs yet. Choose a parser and click Parse to extract this document locally.
            </div>
          )}
          <ul className="space-y-1 pb-2">
            {runs.map((run) => (
              <li key={run.id}>
                <button
                  onClick={() => onViewRun(run)}
                  className={`w-full rounded-md border px-2 py-1.5 text-left text-xs transition-colors ${
                    run.id === activeRunId
                      ? 'border-brand-600 bg-brand-50'
                      : 'border-neutral-200 bg-white hover:border-neutral-300'
                  }`}
                >
                  <div className="flex items-center gap-1.5">
                    <span className={`inline-block h-2 w-2 rounded-full ${STATUS_STYLE[run.status] ?? 'bg-neutral-400'}`} />
                    <span className="font-medium text-neutral-800">{run.providerName}</span>
                    <span className="ml-auto text-neutral-400">{formatTime(run.startedAt)}</span>
                  </div>
                  <div className="mt-0.5 text-neutral-500">
                    {run.status === 'running'
                      ? `Running… ${run.completedPageCount ?? 0}/${run.pageCount} pages`
                      : run.status === 'succeeded'
                        ? `${run.completedPageCount ?? run.pageCount}/${run.pageCount} pages extracted`
                        : (run.errorMessage ?? run.statusMessage ?? run.status)}
                  </div>
                </button>
                {RESUMABLE.has(run.status) && !parsing && (
                  <button
                    onClick={() => onResumeRun(run)}
                    className="ml-1 mt-0.5 text-xs text-brand-700 hover:underline"
                  >
                    Resume from {(run.completedPageCount ?? 0)} pages
                  </button>
                )}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </aside>
  )
}
