# Command-Line Scripts

Rubowar includes several command-line scripts for running battles, tournaments, and logging.

## bin/simulate

Run one or more battles with configurable options and output formats.

```bash
bin/simulate [options] rubot1.rb rubot2.rb [rubot3.rb ...]
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

### Output Options

| Option | Description | Default |
|--------|-------------|---------|
| `-o, --output FORMAT` | Output format: `text`, `json`, `csv` | text |
| `-w, --watch` | Watch battle live in terminal | off |
| `-d, --delay SECONDS` | Delay between frames in watch mode | 0.05 |

### Examples

```bash
# Run a single battle between two rubots
bin/simulate rubots/spinner.rb rubots/hunter.rb

# Watch a battle in real-time
bin/simulate -w rubots/spinner.rb rubots/crusher.rb

# Run 100 battles and output statistics
bin/simulate -n 100 rubots/spinner.rb rubots/hunter.rb

# Reproducible battle with seed
bin/simulate -s 12345 rubots/coroner.rb rubots/evader.rb

# Output as JSON
bin/simulate -o json rubots/spinner.rb rubots/tracker.rb

# Output as CSV (good for spreadsheets)
bin/simulate -n 50 -o csv rubots/spinner.rb rubots/hunter.rb > results.csv

# Custom arena size
bin/simulate -W 800 -H 600 -t 2000 rubots/spinner.rb rubots/hunter.rb
```

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
