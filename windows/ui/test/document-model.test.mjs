import assert from 'node:assert/strict'
import test from 'node:test'
import {
  movePageHistory,
  pagesForMode,
  pushPageHistory,
  searchDocument,
} from '../src/document-model.ts'

test('maps every P0 page layout to the expected pages', () => {
  assert.deepEqual(pagesForMode('single', 3, 6), [3])
  assert.deepEqual(pagesForMode('continuous', 3, 4), [1, 2, 3, 4])
  assert.deepEqual(pagesForMode('grid', 3, 4), [1, 2, 3, 4])
  assert.deepEqual(pagesForMode('two-page', 3, 6), [3, 4])
  assert.deepEqual(pagesForMode('two-page', 4, 6), [3, 4])
  assert.deepEqual(pagesForMode('book', 1, 6), [1])
  assert.deepEqual(pagesForMode('book', 2, 6), [2, 3])
  assert.deepEqual(pagesForMode('book', 6, 6), [6])
})

test('searches every page case-insensitively and counts highlights', () => {
  const results = searchDocument([
    'Alpha beta alpha',
    'Nothing here',
    'ALPHA at the end',
  ], 'alpha')
  assert.deepEqual(results.map(({ page, count }) => ({ page, count })), [
    { page: 1, count: 2 },
    { page: 3, count: 1 },
  ])
  assert.match(results[0].snippet, /Alpha beta alpha/)
})

test('truncates forward page history after a new jump', () => {
  const movedBack = movePageHistory({ history: [1, 4, 8], historyIndex: 2 }, -1)
  assert.equal(movedBack.page, 4)
  const branched = pushPageHistory(movedBack, 6)
  assert.deepEqual(branched, { history: [1, 4, 6], historyIndex: 2 })
  assert.equal(movePageHistory(branched, 1).page, undefined)
})
