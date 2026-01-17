# Command-Line Scripts

Rubowar includes several command-line scripts for running battles, tournaments, and logging.

## bin/battle

Run one or more battles with configurable options, renderers, and output formats.

```bash
bin/battle [options] rubot1.rb rubot2.rb [rubot3.rb ...]
```

If no rubot files are specified, loads all rubots from `rubots/`.

### Arena Options

| Option | Description | Default |
|--------|-------------|---------|
| `-W, --width WIDTH` | Arena width | 480 |
| `-H, --height HEIGHT` | Arena height | 480 |
| `-f, --friction FRICTION` | Friction coefficient | 0.95 |
| `-t, --chronons LIMIT` | Chronon limit per battle | 1000 |

### Simulation Options

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --battles COUNT` | Number of battles to run | 1 |
| `-s, --seed SEED` | Random seed for reproducibility | random |

### Renderer Options

| Option | Description | Default |
|--------|-------------|---------|
| `-w, --watch, --terminal` | Watch battle live in terminal | off |
| `-d, --delay SECONDS` | Delay between frames in watch mode | 0.05 |
| `--html` | Generate HTML replay file in `battle-logs/` | off |
| `--html-dir DIR` | Generate HTML replay in custom directory | - |
| `--json` | Generate JSON log file in `battle-logs/` | off |
| `--json-file FILE` | Generate JSON log to specific file | - |

### Output Options

| Option | Description | Default |
|--------|-------------|---------|
| `-o, --output FORMAT` | Summary format: `text`, `json`, `csv` | text |
| `-q, --quiet` | Suppress summary output (file paths still shown) | off |

### Examples

```bash
# Run a single battle between two rubots
bin/battle rubots/spinner.rb rubots/hunter.rb

# Watch a battle live in terminal
bin/battle --terminal rubots/spinner.rb rubots/crusher.rb
bin/battle -w rubots/spinner.rb rubots/crusher.rb  # short form

# Generate HTML replay
bin/battle --html rubots/spinner.rb rubots/tracker.rb

# Generate JSON log
bin/battle --json rubots/spinner.rb rubots/tracker.rb

# Use all three renderers at once
bin/battle --terminal --html --json rubots/hunter.rb rubots/evader.rb

# Generate files to custom locations
bin/battle --html-dir replays/ --json-file logs/battle.json rubots/spinner.rb rubots/tracker.rb

# Quiet mode (suppresses summary, still shows file paths)
bin/battle --html -q rubots/spinner.rb rubots/tracker.rb

# Run 100 battles and output statistics
bin/battle -n 100 rubots/spinner.rb rubots/hunter.rb

# Reproducible battle with seed
bin/battle -s 12345 rubots/coroner.rb rubots/evader.rb

# Output summary as JSON
bin/battle -o json rubots/spinner.rb rubots/tracker.rb

# Output summary as CSV (good for spreadsheets)
bin/battle -n 50 -o csv rubots/spinner.rb rubots/hunter.rb > results.csv

# Custom arena size
bin/battle -W 800 -H 600 -t 2000 rubots/spinner.rb rubots/hunter.rb

# Battle all rubots in rubots/ directory
bin/battle --html
```

### Renderer Details

**Terminal (`--terminal`, `-w`)**
- Live ASCII/Unicode visualization in terminal
- Use `-d` to adjust frame delay (default: 0.05s)

**HTML (`--html`)**
- Self-contained HTML file with Canvas animation
- Playback controls: Play/Pause, step forward/back, go to start/end
- Speed control: 0.25x to 8x playback speed
- Timeline scrubber: Drag to any point in the battle
- Keyboard shortcuts: Space (play/pause), arrows (step), Home/End
- Smooth animation with interpolation between frames
- Status panel showing health, energy, shield, damage stats

**JSON (`--json`)**
- NDJSON format (one JSON object per line)
- Each line is a frame with rubot positions, bullets, energons
- Final line is battle summary with winner

All files are saved to `battle-logs/` with timestamped names:
- `battle-20260116-143052-spinner-vs-tracker.html`
- `battle-20260116-143052-spinner-vs-tracker.json`

---

## bin/log

Record a battle to JSON for replay, analysis, or external tool integration.

```bash
bin/log [options] rubot1.rb rubot2.rb [rubot3.rb ...]
```

If no rubot files are specified, loads all rubots from `rubots/`.

### Arena Options

| Option | Description | Default |
|--------|-------------|---------|
| `-W, --width WIDTH` | Arena width | 480 |
| `-H, --height HEIGHT` | Arena height | 480 |
| `-f, --friction FRICTION` | Friction coefficient | 0.95 |
| `-t, --chronons LIMIT` | Chronon limit | 1000 |
| `-s, --seed SEED` | Random seed for reproducibility | random |

### Output Options

| Option | Description | Default |
|--------|-------------|---------|
| `-o, --output FILE` | Output file | stdout |
| `-p, --pretty` | Pretty-print JSON | off |
| `--stream` | Stream NDJSON (one object per line) | off |

### Output Format

The JSON output contains:

```json
{
  "metadata": {
    "arena": { "width": 480, "height": 480, "friction": 0.95 },
    "rubots": [
      { "name": "Spinner", "size": "medium", "id": "uuid-here" }
    ],
    "recorded_at": "2024-01-15T10:30:00Z"
  },
  "frames": [
    {
      "type": "tick",
      "chronon": 1,
      "rubots": [
        {
          "id": "uuid", "name": "Spinner",
          "x": 100.5, "y": 200.3,
          "velocity_x": 0.0, "velocity_y": 0.0,
          "speed": 0.0, "turret_angle": 45.0,
          "health": 100, "energy": 100, "shield_level": 0,
          "damage_dealt": 0, "damage_taken": 0,
          "size": "medium", "alive": true
        }
      ],
      "bullets": [
        { "x": 150.0, "y": 180.0, "velocity_x": 18.0, "velocity_y": 0.0 }
      ],
      "energons": [
        { "x": 400.0, "y": 300.0, "spawn_chronon": 80, "current_value": 25 }
      ]
    },
    {
      "type": "summary",
      "winner": { "id": "uuid", "name": "Spinner", ... },
      "outcome": "victory",
      "duration_ms": 1234
    }
  ]
}
```

### Streaming Mode (NDJSON)

With `--stream`, outputs newline-delimited JSON (one object per line) instead of a single JSON array. This is useful for:
- Real-time log processing
- Large battles that shouldn't be held in memory
- Piping to tools like `jq`

### Examples

```bash
# Log to stdout (compact JSON)
bin/log rubots/spinner.rb rubots/hunter.rb

# Log to file with pretty-print
bin/log -o replay.json -p rubots/spinner.rb rubots/hunter.rb

# Reproducible battle
bin/log -s 12345 -o battle.json rubots/coroner.rb rubots/evader.rb

# Stream NDJSON to file
bin/log --stream -o battle.ndjson rubots/spinner.rb rubots/hunter.rb

# Pipe to jq for analysis
bin/log -t 100 | jq '.frames[-1]'

# Extract just the winner
bin/log -t 500 | jq '.frames[] | select(.type == "summary") | .winner.name'

# Count total damage dealt
bin/log -t 1000 | jq '[.frames[] | select(.type == "tick") | .rubots[].damage_dealt] | max'
```

---

## bin/tournament

Run a full tournament across all rubots in the `rubots/` directory with 1v1, 1v1v1, and 1v1v1v1 formats.

```bash
bin/tournament
```

No options - runs a comprehensive tournament with:
- All combinations of rubots
- 64 iterations per combination
- 1v1, 1v1v1, and 1v1v1v1 formats
- Points-based scoring

### Output

Produces a results table showing points earned in each format:

```
================================================================================
TOURNAMENT RESULTS
================================================================================

| Rubot        |  1v1 Total |  1v1v1 Total |  1v1v1v1 Total |  Grand Total |
|--------------|------------|--------------|----------------|--------------|
| Coroner      |       2048 |         4320 |           5760 |        12128 |
| Spinner      |       1536 |         3456 |           4608 |         9600 |
| ...
```

### Scoring

- **1v1**: Winner gets N points (N = number of rubots)
- **1v1v1**: 1st: 3 pts, 2nd: 2 pts, 3rd: 1 pt
- **1v1v1v1**: 1st: 4 pts, 2nd: 3 pts, 3rd: 2 pts, 4th: 1 pt

---

## bin/console

Start an interactive Ruby console with Rubowar loaded.

```bash
bin/console
```

Useful for experimenting with the API:

```ruby
# In console
battle = Rubowar::Battle.local([Spinner, Hunter])
battle.run
puts battle.winner.rubot_class.name
```

---

## bin/setup

Install dependencies and set up the development environment.

```bash
bin/setup
```
