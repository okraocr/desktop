import type { Block } from '../types'

interface Props {
  blocks: Block[]
  selectedId: string | null
  hoveredId: string | null
  onHover: (id: string | null) => void
  onSelect: (id: string) => void
}

// Screen-only, removable boxes over the rendered PDF page (the WebView
// equivalent of the macOS PDFKit bounding-box annotations).
export function BoxOverlay({ blocks, selectedId, hoveredId, onHover, onSelect }: Props) {
  return (
    <div className="pointer-events-none absolute inset-0">
      {blocks.map((block) => {
        if (!block.bbox) return null
        const isSelected = block.id === selectedId
        const isHovered = block.id === hoveredId
        return (
          <div
            key={block.id}
            onMouseEnter={() => onHover(block.id)}
            onMouseLeave={() => onHover(null)}
            onClick={() => onSelect(block.id)}
            title={block.text.slice(0, 120)}
            className={`pointer-events-auto absolute cursor-pointer rounded-[2px] border transition-colors ${
              isSelected
                ? 'border-brand-600 bg-brand-400/20'
                : isHovered
                  ? 'border-amber-500 bg-amber-300/15'
                  : 'border-brand-600/60 bg-brand-400/5 hover:bg-brand-400/15'
            }`}
            style={{
              left: `${block.bbox.x * 100}%`,
              top: `${block.bbox.y * 100}%`,
              width: `${block.bbox.width * 100}%`,
              height: `${block.bbox.height * 100}%`,
            }}
          />
        )
      })}
    </div>
  )
}
