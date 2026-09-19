import type { EngineInterface, Register, RenderInput, Timer } from 'claude-code'

const LANE_DIR = '/tmp/maestro-lanes'
const POLL_MS = 2_000
const FINISHED_MS = 10 * 60 * 1_000
const STALE_MS = 65 * 60 * 1_000
const LANE_FILE = /^(luna|grok|astra|research)\.(.+)$/
const EXIT_LINE = /^maestro-exit:\s*(-?\d+)$/i
const RATE_LIMITED =
  /usage limit|rate limit|quota|429|402|payment required|balance exhausted|unauthorized|not logged in/i

const MODEL_OF = {
  luna: 'GPT-5.6 Luna max',
  grok: 'Grok 4.6 medium',
  astra: 'GPT-6 Astra high',
  research: 'Grok 4.6 medium (plan)',
} as const

type Lane = keyof typeof MODEL_OF

type LaneFile = {
  lane: Lane
  suffix: string
  mtimeMs: number
  firstSeenMs: number
  body: string
}

type LaneState = {
  sessionStartMs: number | undefined
  firstSeen: Map<string, number>
  rows: string[]
  stamp: string
  isRefreshing: boolean
}

function elapsedOf(ms: number): string {
  const seconds = Math.max(0, Math.floor(ms / 1_000))

  if (seconds < 60) {
    return `${seconds}s`
  }

  return `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, '0')}s`
}

function rowOf(file: LaneFile, now: number): string | null {
  const lines = file.body
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line !== '')
  const exit = lines.findLast(line => EXIT_LINE.test(line))?.match(EXIT_LINE)
  const exitCode = exit?.[1] === undefined ? undefined : Number(exit[1])
  const isFinished = exitCode !== undefined

  if (isFinished && now - file.mtimeMs > FINISHED_MS) {
    return null
  }

  let state = 'running'

  if (exitCode === 0) {
    state = 'done'
  } else if (exitCode !== undefined) {
    // ponytail: tail-20 heuristic, a structured exit reason from the lane if it misfires
    state = lines.slice(-20).some(line => RATE_LIMITED.test(line))
      ? 'rate-limited'
      : `failed (${exitCode})`
  } else if (now - file.mtimeMs > STALE_MS) {
    // ponytail: mtime heuristic, a pid file if it misfires
    state = 'stale'
  }

  const elapsed = isFinished
    ? file.mtimeMs - file.firstSeenMs
    : now - file.firstSeenMs
  const output = lines.findLast(line => !EXIT_LINE.test(line))
  const row = `${file.lane} ${file.suffix} · ${MODEL_OF[file.lane]} · ${state} · ${elapsedOf(elapsed)}`

  return output === undefined ? row : `${row} · ${output}`
}

async function rowsOf(
  $: EngineInterface,
  state: LaneState,
  sessionStartMs: number,
  now: number,
): Promise<string[]> {
  let entries

  try {
    entries = await $.fs.list(LANE_DIR)
  } catch {
    return []
  }

  const files = await Promise.all(
    entries.map(async entry => {
      const match = entry.kind === 'file' ? entry.name.match(LANE_FILE) : null

      if (!match) {
        return null
      }

      const path = `${LANE_DIR}/${entry.name}`

      try {
        const stat = await $.fs.stat(path)

        if (stat.kind !== 'file' || stat.mtimeMs < sessionStartMs) {
          return null
        }

        // $.fs.stat has no birth time: a run starts when a poll first sees it.
        if (!state.firstSeen.has(path)) {
          state.firstSeen.set(path, now)
        }

        return {
          lane: match[1] as Lane,
          suffix: match[2] ?? '',
          mtimeMs: stat.mtimeMs,
          firstSeenMs: state.firstSeen.get(path) ?? now,
          body: await $.fs.read(path),
        }
      } catch {
        return null
      }
    }),
  )

  return files
    .map(file => (file === null ? null : rowOf(file, now)))
    .filter((row): row is string => row !== null)
}

function bandOf(
  $: EngineInterface,
  e: RenderInput<'AbovePrompt', 'terminal'>,
  rows: readonly string[],
) {
  const { Box, Text } = $.ui.resolve(e)

  return Box({
    flexDirection: 'column',
    children: rows.map(row => Text({ wrap: 'truncate-end', children: row })),
  })
}

async function refresh(
  $: EngineInterface,
  state: LaneState,
  invalidate: boolean,
): Promise<void> {
  if (state.sessionStartMs === undefined || state.isRefreshing) {
    return
  }

  state.isRefreshing = true

  try {
    const now = await $.clock.now()
    const nextRows = await rowsOf($, state, state.sessionStartMs, now)
    const nextStamp = nextRows.join('\n')
    const changed = nextStamp !== state.stamp

    state.rows = nextRows
    state.stamp = nextStamp

    if (invalidate && changed) {
      $.ui.invalidate('ui.render')
    }
  } finally {
    state.isRefreshing = false
  }
}

export const register: Register = (on, _options) => {
  const state: LaneState = {
    sessionStartMs: undefined,
    firstSeen: new Map(),
    rows: [],
    stamp: '',
    isRefreshing: false,
  }
  let poll: Timer | undefined

  on('session.start', async ($, e, next) => {
    state.sessionStartMs = await $.clock.now()
    poll?.cancel()
    await refresh($, state, false)
    poll = $.clock.every(POLL_MS, () => {
      void refresh($, state, true)
    })

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || e.surface !== 'terminal') {
      return next(e)
    }

    await refresh($, state, false)

    if (state.rows.length === 0) {
      return next(e)
    }

    return bandOf($, e, state.rows)
  })
}
