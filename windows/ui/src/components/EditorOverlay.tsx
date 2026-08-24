import { useEffect, useMemo, useRef, useState } from 'react'
import { createAnnotationId } from '../editor'
import type { AnnotationTool, EditorAnnotation, EditorPoint } from '../editor'

interface Props {
  page: number
  tool: AnnotationTool
  annotations: EditorAnnotation[]
  selectedId: string | null
  color: string
  opacity: number
  lineWidth: number
  fontSize: number
  imageDataUrl: string | null
  onAdd: (annotation: EditorAnnotation) => void
  onUpdate: (annotation: EditorAnnotation) => void
  onSelect: (id: string | null) => void
}

interface Gesture {
  start: EditorPoint
  current: EditorPoint
  points: EditorPoint[]
}

export function EditorOverlay(props: Props) {
  const container = useRef<HTMLDivElement>(null)
  const [gesture, setGesture] = useState<Gesture | null>(null)
  const pageAnnotations = useMemo(
    () => props.annotations.filter((annotation) => annotation.page === props.page),
    [props.annotations, props.page],
  )

  function pointFromEvent(event: React.PointerEvent): EditorPoint {
    const rect = container.current?.getBoundingClientRect()
    if (!rect) return { x: 0, y: 0 }
    return {
      x: Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width)),
      y: Math.min(1, Math.max(0, (event.clientY - rect.top) / rect.height)),
    }
  }

  function addImmediate(point: EditorPoint) {
    if (props.tool === 'text') {
      props.onAdd(baseAnnotation(props, 'text', point.x, point.y, 0.28, 0.08, { text: 'Text' }))
    } else if (props.tool === 'image' && props.imageDataUrl) {
      props.onAdd(baseAnnotation(props, 'image', point.x, point.y, 0.28, 0.2, { imageDataUrl: props.imageDataUrl }))
    }
  }

  function onPointerDown(event: React.PointerEvent) {
    if (props.tool === 'select') {
      if (event.target === event.currentTarget) props.onSelect(null)
      return
    }
    const point = pointFromEvent(event)
    if (props.tool === 'text' || props.tool === 'image') {
      addImmediate(point)
      return
    }
    event.currentTarget.setPointerCapture(event.pointerId)
    setGesture({ start: point, current: point, points: [point] })
  }

  function onPointerMove(event: React.PointerEvent) {
    if (!gesture) return
    const point = pointFromEvent(event)
    setGesture((current) => current && ({
      ...current,
      current: point,
      points: props.tool === 'draw' ? [...current.points, point] : current.points,
    }))
  }

  function onPointerUp(event: React.PointerEvent) {
    if (!gesture) return
    const point = pointFromEvent(event)
    const left = Math.min(gesture.start.x, point.x)
    const top = Math.min(gesture.start.y, point.y)
    const width = Math.max(0.002, Math.abs(point.x - gesture.start.x))
    const height = Math.max(0.002, Math.abs(point.y - gesture.start.y))
    const kind = props.tool === 'select' || props.tool === 'text' || props.tool === 'image' ? null : props.tool
    if (kind) {
      const options = kind === 'draw'
        ? { points: [...gesture.points, point] }
        : kind === 'line'
          ? { points: [gesture.start, point] }
          : undefined
      props.onAdd(baseAnnotation(props, kind, left, top, width, height, options))
    }
    setGesture(null)
  }

  const preview = gesture ? gestureAnnotation(props, gesture) : null
  return (
    <div
      ref={container}
      className={`absolute inset-0 ${props.tool === 'select' ? 'pointer-events-none' : 'cursor-crosshair touch-none'}`}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
    >
      {pageAnnotations.map((annotation) => (
        <AnnotationView
          key={annotation.id}
          annotation={annotation}
          selected={annotation.id === props.selectedId}
          selectable={props.tool === 'select'}
          onSelect={() => props.onSelect(annotation.id)}
          onUpdate={props.onUpdate}
        />
      ))}
      {preview && <AnnotationView annotation={preview} selected={false} selectable={false} onSelect={() => {}} onUpdate={() => {}} />}
    </div>
  )
}

function baseAnnotation(
  props: Props,
  kind: EditorAnnotation['kind'],
  x: number,
  y: number,
  width: number,
  height: number,
  options?: Partial<EditorAnnotation>,
): EditorAnnotation {
  return {
    id: createAnnotationId(),
    page: props.page,
    kind,
    x,
    y,
    width,
    height,
    color: props.color,
    fillColor: kind === 'highlight' ? props.color : undefined,
    opacity: kind === 'highlight' ? Math.min(props.opacity, 0.45) : props.opacity,
    lineWidth: props.lineWidth,
    fontSize: props.fontSize,
    ...options,
  }
}

function gestureAnnotation(props: Props, gesture: Gesture): EditorAnnotation | null {
  if (props.tool === 'select' || props.tool === 'text' || props.tool === 'image') return null
  const x = Math.min(gesture.start.x, gesture.current.x)
  const y = Math.min(gesture.start.y, gesture.current.y)
  return baseAnnotation(
    props,
    props.tool,
    x,
    y,
    Math.max(0.002, Math.abs(gesture.current.x - gesture.start.x)),
    Math.max(0.002, Math.abs(gesture.current.y - gesture.start.y)),
    props.tool === 'draw'
      ? { points: gesture.points }
      : props.tool === 'line'
        ? { points: [gesture.start, gesture.current] }
        : undefined,
  )
}

interface AnnotationViewProps {
  annotation: EditorAnnotation
  selected: boolean
  selectable: boolean
  onSelect: () => void
  onUpdate: (annotation: EditorAnnotation) => void
}

function AnnotationView({ annotation, selected, selectable, onSelect, onUpdate }: AnnotationViewProps) {
  const style: React.CSSProperties = {
    left: `${annotation.x * 100}%`,
    top: `${annotation.y * 100}%`,
    width: `${annotation.width * 100}%`,
    height: `${annotation.height * 100}%`,
    opacity: annotation.opacity,
  }
  const frameClass = selected ? 'outline outline-2 outline-offset-1 outline-brand-500' : ''
  const pointerClass = selectable ? 'pointer-events-auto cursor-pointer' : 'pointer-events-none'

  if (annotation.kind === 'draw') {
    return (
      <svg className="pointer-events-none absolute inset-0 h-full w-full" viewBox="0 0 1 1" preserveAspectRatio="none">
        <polyline
          points={(annotation.points ?? []).map((point) => `${point.x},${point.y}`).join(' ')}
          fill="none"
          stroke={annotation.color}
          strokeWidth={annotation.lineWidth / 600}
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity={annotation.opacity}
          className={`${frameClass} ${selectable ? 'pointer-events-auto cursor-pointer' : ''}`}
          onPointerDown={(event) => { event.stopPropagation(); onSelect() }}
        />
      </svg>
    )
  }

  if (annotation.kind === 'line') {
    const start = annotation.points?.[0]
    const end = annotation.points?.[1]
    return (
      <svg className={`pointer-events-none absolute inset-0 h-full w-full ${frameClass}`} viewBox="0 0 1 1" preserveAspectRatio="none">
        <line
          x1={start?.x ?? annotation.x}
          y1={start?.y ?? annotation.y}
          x2={end?.x ?? annotation.x + annotation.width}
          y2={end?.y ?? annotation.y + annotation.height}
          stroke={annotation.color}
          strokeWidth={annotation.lineWidth / 600}
          vectorEffect="non-scaling-stroke"
          className={selectable ? 'pointer-events-auto cursor-pointer' : 'pointer-events-none'}
          onPointerDown={(event) => { event.stopPropagation(); onSelect() }}
        />
      </svg>
    )
  }

  if (annotation.kind === 'text') {
    return <EditableText annotation={annotation} selected={selected} selectable={selectable} onSelect={onSelect} onUpdate={onUpdate} style={style} />
  }

  if (annotation.kind === 'image') {
    return (
      <img
        src={annotation.imageDataUrl}
        alt="Inserted annotation"
        draggable={false}
        className={`absolute object-contain ${pointerClass} ${frameClass}`}
        style={style}
        onPointerDown={(event) => { event.stopPropagation(); onSelect() }}
      />
    )
  }

  const common = {
    className: `absolute ${pointerClass} ${frameClass}`,
    style,
    onPointerDown: (event: React.PointerEvent) => { event.stopPropagation(); onSelect() },
  }
  if (annotation.kind === 'highlight') {
    return <div {...common} style={{ ...style, backgroundColor: annotation.color, mixBlendMode: 'multiply' }} />
  }
  if (annotation.kind === 'underline') {
    return <div {...common} style={{ ...style, borderBottom: `${annotation.lineWidth}px solid ${annotation.color}` }} />
  }
  if (annotation.kind === 'strikeout') {
    return <div {...common}><span className="absolute left-0 right-0 top-1/2" style={{ borderTop: `${annotation.lineWidth}px solid ${annotation.color}` }} /></div>
  }
  if (annotation.kind === 'ellipse') {
    return <div {...common} style={{ ...style, border: `${annotation.lineWidth}px solid ${annotation.color}`, borderRadius: '9999px' }} />
  }
  return <div {...common} style={{ ...style, border: `${annotation.lineWidth}px solid ${annotation.color}` }} />
}

function EditableText({ annotation, selected, selectable, onSelect, onUpdate, style }: AnnotationViewProps & { style: React.CSSProperties }) {
  const [value, setValue] = useState(annotation.text ?? '')
  useEffect(() => setValue(annotation.text ?? ''), [annotation.text])
  return (
    <textarea
      value={value}
      readOnly={!selected}
      aria-label="Text annotation"
      className={`absolute resize-none overflow-hidden border-0 bg-transparent p-1 ${selectable ? 'pointer-events-auto' : 'pointer-events-none'} ${selected ? 'outline outline-2 outline-brand-500' : 'outline-none'}`}
      style={{ ...style, color: annotation.color, fontSize: `${annotation.fontSize}px`, opacity: annotation.opacity }}
      onPointerDown={(event) => { event.stopPropagation(); onSelect() }}
      onChange={(event) => setValue(event.target.value)}
      onBlur={() => {
        if (value !== annotation.text) onUpdate({ ...annotation, text: value })
      }}
    />
  )
}
