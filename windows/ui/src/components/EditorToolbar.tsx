import { useRef } from 'react'
import type { AnnotationTool } from '../editor'

interface Props {
  tool: AnnotationTool
  color: string
  opacity: number
  lineWidth: number
  fontSize: number
  canUndo: boolean
  canRedo: boolean
  dirty: boolean
  selected: boolean
  onToolChange: (tool: AnnotationTool) => void
  onColorChange: (color: string) => void
  onOpacityChange: (opacity: number) => void
  onLineWidthChange: (width: number) => void
  onFontSizeChange: (size: number) => void
  onImageChange: (dataUrl: string) => void
  onUndo: () => void
  onRedo: () => void
  onDelete: () => void
  onSave: () => void
}

const TOOLS: { id: AnnotationTool; label: string; shortcut: string }[] = [
  { id: 'select', label: 'Select', shortcut: 'V' },
  { id: 'text', label: 'Text', shortcut: 'T' },
  { id: 'highlight', label: 'Highlight', shortcut: 'H' },
  { id: 'underline', label: 'Underline', shortcut: 'U' },
  { id: 'strikeout', label: 'Strike', shortcut: 'K' },
  { id: 'draw', label: 'Draw', shortcut: 'D' },
  { id: 'line', label: 'Line', shortcut: 'L' },
  { id: 'rectangle', label: 'Box', shortcut: 'R' },
  { id: 'ellipse', label: 'Ellipse', shortcut: 'E' },
  { id: 'image', label: 'Image', shortcut: 'I' },
]

export function EditorToolbar(props: Props) {
  const imageInput = useRef<HTMLInputElement>(null)
  return (
    <div className="flex min-h-10 shrink-0 flex-wrap items-center gap-1 border-b border-neutral-200 bg-white px-2 py-1">
      {TOOLS.map((item) => (
        <button
          key={item.id}
          title={`${item.label} (${item.shortcut})`}
          aria-pressed={props.tool === item.id}
          onClick={() => {
            props.onToolChange(item.id)
            if (item.id === 'image') imageInput.current?.click()
          }}
          className={`rounded px-2 py-1 text-xs ${
            props.tool === item.id ? 'bg-brand-700 text-white' : 'border border-neutral-200 text-neutral-700 hover:bg-neutral-100'
          }`}
        >
          {item.label}
        </button>
      ))}
      <input
        ref={imageInput}
        type="file"
        accept="image/png,image/jpeg"
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0]
          if (!file) return
          const reader = new FileReader()
          reader.onload = () => {
            if (typeof reader.result === 'string') props.onImageChange(reader.result)
          }
          reader.readAsDataURL(file)
          event.currentTarget.value = ''
        }}
      />
      <span className="mx-1 h-5 w-px bg-neutral-200" />
      <label className="flex items-center gap-1 text-[11px] text-neutral-500">
        Color
        <input type="color" value={props.color} onChange={(event) => props.onColorChange(event.target.value)} className="h-6 w-7" />
      </label>
      <label className="flex items-center gap-1 text-[11px] text-neutral-500">
        Opacity
        <input type="range" min="10" max="100" value={Math.round(props.opacity * 100)} onChange={(event) => props.onOpacityChange(Number(event.target.value) / 100)} className="w-20" />
      </label>
      <label className="flex items-center gap-1 text-[11px] text-neutral-500">
        Width
        <input type="number" min="1" max="20" value={props.lineWidth} onChange={(event) => props.onLineWidthChange(Number(event.target.value))} className="w-12 rounded border border-neutral-300 px-1 py-0.5" />
      </label>
      {props.tool === 'text' && (
        <label className="flex items-center gap-1 text-[11px] text-neutral-500">
          Size
          <input type="number" min="6" max="72" value={props.fontSize} onChange={(event) => props.onFontSizeChange(Number(event.target.value))} className="w-14 rounded border border-neutral-300 px-1 py-0.5" />
        </label>
      )}
      <span className="ml-auto" />
      <button disabled={!props.selected} onClick={props.onDelete} className="rounded border border-neutral-200 px-2 py-1 text-xs disabled:opacity-40">Delete</button>
      <button disabled={!props.canUndo} onClick={props.onUndo} className="rounded border border-neutral-200 px-2 py-1 text-xs disabled:opacity-40">Undo</button>
      <button disabled={!props.canRedo} onClick={props.onRedo} className="rounded border border-neutral-200 px-2 py-1 text-xs disabled:opacity-40">Redo</button>
      <button disabled={!props.dirty} onClick={props.onSave} className="rounded bg-brand-700 px-3 py-1 text-xs font-medium text-white disabled:opacity-40">Save a copy</button>
    </div>
  )
}
