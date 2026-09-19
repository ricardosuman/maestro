import type { On, RenderElement, RenderInput } from 'claude-code'
import { describe, expect, mock, test, tier } from 'claude-code/testing'

tier('builtin')

const SESSION_START = 1_000_000
const LANE_DIR = '/tmp/maestro-lanes/'
const SESSION = { surface: 'terminal', isInteractive: true, cwd: '/work' } as const
const BAND = {
  surface: 'terminal',
  component: 'AbovePrompt',
  requestId: 'above-prompt',
  props: {
    hasSurvey: false,
    isWorking: true,
    maxRows: 10,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} satisfies RenderInput<'AbovePrompt', 'terminal'>
// What the engine draws above the prompt when the mod passes to next.
const ENGINE_BAND: RenderElement = { type: 'Text', children: ['engine band'] }

type LaneFile = {
  name: string
  body: string
  mtimeMs: number
}

function installFs(on: On, files: readonly LaneFile[]) {
  on('fs.list', () => ({
    value: files.map(file => ({
      name: file.name,
      kind: 'file' as const,
      size: file.body.length,
      isLink: false,
    })),
  }))

  on('fs.stat', ($, e) => {
    const file = files.find(candidate => `${LANE_DIR}${candidate.name}` === e.path)

    return file === undefined
      ? { deny: 'missing test file' }
      : {
          value: {
            kind: 'file' as const,
            size: file.body.length,
            mtimeMs: file.mtimeMs,
            isLink: false,
          },
        }
  })

  on('fs.read', ($, e) => {
    const file = files.find(candidate => `${LANE_DIR}${candidate.name}` === e.path)

    return file === undefined
      ? { deny: 'missing test file' }
      : { value: file.body }
  })
}

function startWorld(on: On, files: readonly LaneFile[]) {
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  const clock = mock.clock(on, { now: SESSION_START })
  installFs(on, files)
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.render', { component: 'AbovePrompt' }, () => ENGINE_BAND)

  return clock
}

function textOf(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') {
    return String(value)
  }

  if (Array.isArray(value)) {
    return value.map(textOf).join('')
  }

  if (typeof value !== 'object' || value === null) {
    return ''
  }

  const record = value as { children?: unknown; props?: { label?: unknown; source?: unknown } }
  const label = typeof record.props?.label === 'string' ? record.props.label : ''
  const source = typeof record.props?.source === 'string' ? record.props.source : ''

  return `${label}${source}${textOf(record.children)}`
}

describe('register', () => {
  test('a running file renders a running row', async ($, on) => {
    startWorld(on, [
      { name: 'luna.ABC123', body: 'working line\n', mtimeMs: SESSION_START },
    ])

    await $.session.start(SESSION)

    const drawn = textOf(await $.ui.render(BAND))

    expect(drawn).toContain('luna ABC123')
    expect(drawn).toContain('GPT-5.6 Luna max')
    expect(drawn).toContain('running')
    expect(drawn).toContain('working line')
  })

  test('a zero exit renders done', async ($, on) => {
    startWorld(on, [
      {
        name: 'grok.done42',
        body: 'finished line\nmaestro-exit: 0\n',
        mtimeMs: SESSION_START + 5_000,
      },
    ])

    await $.session.start(SESSION)

    const drawn = textOf(await $.ui.render(BAND))

    expect(drawn).toContain('grok done42')
    expect(drawn).toContain('done')
    expect(drawn).toContain('finished line')
  })

  test('a rate-limited non-zero exit renders rate-limited', async ($, on) => {
    startWorld(on, [
      {
        name: 'research.limit7',
        body: 'rate limit reached\nmaestro-exit: 7\n',
        mtimeMs: SESSION_START + 5_000,
      },
    ])

    await $.session.start(SESSION)

    expect(textOf(await $.ui.render(BAND))).toContain('rate-limited')
  })

  test('rate limit only before the last 20 lines renders failed', async ($, on) => {
    const later = Array.from({ length: 25 }, (_, at) => `line ${at}`).join('\n')

    startWorld(on, [
      {
        name: 'grok.echo3',
        body: `rate limit in the prompt echo\n${later}\nmaestro-exit: 3\n`,
        mtimeMs: SESSION_START + 5_000,
      },
    ])

    await $.session.start(SESSION)

    const drawn = textOf(await $.ui.render(BAND))

    expect(drawn).toContain('failed (3)')
    expect(drawn).not.toContain('rate-limited')
  })

  test('elapsed counts from when each run was first seen', async ($, on) => {
    const files: LaneFile[] = [
      { name: 'luna.first', body: 'one\n', mtimeMs: SESSION_START },
    ]
    const clock = startWorld(on, files)

    await $.session.start(SESSION)
    await clock.advance(30_000)
    files.push({ name: 'grok.second', body: 'two\n', mtimeMs: SESSION_START + 30_000 })

    const drawn = textOf(await $.ui.render(BAND))

    expect(drawn).toContain('luna first · GPT-5.6 Luna max · running · 30s')
    expect(drawn).toContain('grok second · Grok 4.6 medium · running · 0s')
  })

  test('a file older than the session start is not shown', async ($, on) => {
    startWorld(on, [
      {
        name: 'astra.old99',
        body: 'old output\n',
        mtimeMs: SESSION_START - 1,
      },
    ])

    await $.session.start(SESSION)

    expect(await $.ui.render(BAND)).toEqual(ENGINE_BAND)
  })

  test('no files draws nothing', async ($, on) => {
    startWorld(on, [])

    await $.session.start(SESSION)

    expect(await $.ui.render(BAND)).toEqual(ENGINE_BAND)
  })
})
