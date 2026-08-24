import type { RedactionBox } from '../types'

interface Props {
  boxes: RedactionBox[]
  enabledIds: Set<string>
  selectedId: string | null
  hoveredId: string | null
  onHover: (id: string | null) => void
  onSelect: (id: string) => void
}

// Review-only overlay. Export rasterizes approved boxes into a new PDF; this
// component never mutates or draws onto the source document.
export function RedactionOverlay({ boxes, enabledIds, selectedId, hoveredId, onHover, onSelect }: Props) {
  return (
    <div className="pointer-events-none absolute inset-0">
      {boxes.map((box) => {
        const enabled = enabledIds.has(box.id)
        const selected = box.id === selectedId
        const hovered = box.id === hoveredId
        return (
          <button
            key={box.id}
            type="button"
            onMouseEnter={() => onHover(box.id)}
            onMouseLeave={() => onHover(null)}
            onClick={() => onSelect(box.id)}
            title={`${box.type}: ${box.text}`}
            aria-label={`${enabled ? 'Approved' : 'Excluded'} ${box.type} redaction`}
            className={`pointer-events-auto absolute border transition-colors ${
              enabled
                ? selected || hovered
                  ? 'border-amber-400 bg-black/80'
                  : 'border-black bg-black/65'
                : selected || hovered
                  ? 'border-amber-500 bg-amber-200/20'
                  : 'border-dashed border-neutral-500 bg-white/10'
            }`}
            style={{
              left: `${box.x * 100}%`,
              top: `${box.y * 100}%`,
              width: `${box.w * 100}%`,
              height: `${box.h * 100}%`,
            }}
          />
        )
      })}
    </div>
  )
}
