import assert from 'node:assert/strict'
import test from 'node:test'
import { createRequire } from 'node:module'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const uiRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

async function renderSmokeComponents() {
  const source = `
    import React from 'react'
    import { renderToStaticMarkup } from 'react-dom/server'
    import { DocumentTabs } from './src/components/DocumentTabs.tsx'
    import { EditorToolbar } from './src/components/EditorToolbar.tsx'
    const noop = () => {}
    export const tabs = renderToStaticMarkup(React.createElement(DocumentTabs, {
      documents: [
        { id: 'first', fileName: 'first.pdf', dirty: true },
        { id: 'second', fileName: 'second.pdf', dirty: false },
      ],
      activeId: 'first', splitId: 'second', onActivate: noop, onClose: noop,
      onOpen: noop, onSplitChange: noop,
    }))
    export const editor = renderToStaticMarkup(React.createElement(EditorToolbar, {
      tool: 'highlight', color: '#fde047', opacity: 0.5, lineWidth: 2, fontSize: 14,
      canUndo: true, canRedo: true, dirty: true, selected: true,
      onToolChange: noop, onColorChange: noop, onOpacityChange: noop,
      onLineWidthChange: noop, onFontSizeChange: noop, onImageChange: noop,
      onUndo: noop, onRedo: noop, onDelete: noop, onSave: noop,
    }))
  `
  const result = await build({
    stdin: { contents: source, resolveDir: uiRoot, loader: 'tsx' },
    bundle: true,
    format: 'cjs',
    platform: 'node',
    packages: 'external',
    write: false,
  })
  const module = { exports: {} }
  const execute = new Function('require', 'module', 'exports', '__dirname', '__filename', result.outputFiles[0].text)
  execute(createRequire(import.meta.url), module, module.exports, uiRoot, resolve(uiRoot, 'component-smoke.cjs'))
  return module.exports
}

test('renders accessible document tabs, dirty state, and split selection', async () => {
  const { tabs } = await renderSmokeComponents()
  assert.match(tabs, /role="tablist"/)
  assert.match(tabs, /aria-selected="true"/)
  assert.match(tabs, /Close first\.pdf/)
  assert.match(tabs, /Unsaved edits/)
  assert.match(tabs, /<option value="second" selected="">second\.pdf<\/option>/)
})

test('renders the complete P0 annotation toolbar with stateful actions', async () => {
  const { editor } = await renderSmokeComponents()
  for (const label of ['Select', 'Text', 'Highlight', 'Underline', 'Strike', 'Draw', 'Line', 'Box', 'Ellipse', 'Image']) {
    assert.match(editor, new RegExp(`>${label}<`))
  }
  assert.match(editor, /aria-pressed="true"[^>]*>Highlight</)
  assert.match(editor, />Undo</)
  assert.match(editor, />Redo</)
  assert.match(editor, />Save a copy</)
})
