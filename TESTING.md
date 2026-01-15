# Testing Guidelines

## Framework

We use Minitest with spec-style syntax (`describe`, `it`).

## Style

### Arrange, Act, Assert

Every test should clearly separate three phases:

```ruby
it "describes the expected behavior" do
  # Arrange - set up test data
  bot = TestBot.new
  bot.actions = { sense: [], move: [], combat: [] }

  # Act - perform the action being tested
  bot.thrust(speed: 5, angle: 90)

  # Assert - verify the result
  _(bot.actions[:move]).must_equal [{ type: :thrust, speed: 5, angle: 90 }]
end
```

### Atomic Tests

Each test must be completely independent:
- No shared instance variables (`@var`)
- No `before` blocks that set up shared state
- Each test creates its own fixtures
- Tests can run in any order

### Helper Methods

Use helper methods to build common fixtures:

```ruby
def build_bot(energy: 50, health: 100)
  bot = TestBot.new
  bot.rubot_state = Rubowar::RubotState.new(
    x: 100.0, y: 200.0,
    velocity_x: 0.0, velocity_y: 0.0,
    speed: 0.0,
    turret_angle: 0.0,
    health: health, energy: energy, shield_level: 0,
    damage_dealt: 0, damage_taken: 0,
    size: :medium
  )
  bot.actions = { sense: [], move: [], combat: [] }
  bot
end
```

### Naming

- `describe` blocks name the class or method being tested
- `it` blocks describe the expected behavior in plain English
- Use "when" for context: `describe "when energy is zero"`

### One Assertion Per Test (When Practical)

Prefer focused tests with a single assertion. Multiple assertions are okay when testing related properties of a single result.

```ruby
# Good - single behavior
it "ignores zero energy" do
  bot = build_bot
  bot.thrust(0)
  _(bot.actions).must_be_empty
end

# Good - related properties of one result
it "creates a bullet with correct properties" do
  bullet = Rubowar::Bullet.new(x: 100, y: 200, angle: 45, damage: 15, owner: actor)
  _(bullet.x).must_equal 100
  _(bullet.y).must_equal 200
  _(bullet.damage).must_equal 15
end

# Avoid - testing unrelated behaviors
it "does multiple things" do
  bot.thrust(0)
  _(bot.actions).must_be_empty
  bot.thrust(10)
  _(bot.actions.length).must_equal 1  # Now testing something else
end
```

## File Organization

- One test file per source file: `lib/rubowar/bullet.rb` → `test/bullet_test.rb`
- Test file names end with `_test.rb`
- Require `test_helper` at the top of each test file

## Testing Phased Actions

Actions are organized into three phases: `sense`, `move`, and `combat`. Each phase executes for all rubots before the next phase begins.

### Action Phase Mapping

| Method | Phase | Action Type |
|--------|-------|-------------|
| `probe`, `scan`, `pulse`, `detect` | `:sense` | Sensing actions |
| `thrust`, `rotate_turret` | `:move` | Movement actions |
| `fire`, `raise_shields` | `:combat` | Combat actions |

### Testing Action Queueing

Test that actions queue to the correct phase:

```ruby
it "queues thrust to move phase" do
  bot = build_bot

  bot.thrust(speed: 5, angle: 90)

  _(bot.actions[:move]).must_equal [{ type: :thrust, speed: 5, angle: 90 }]
  _(bot.actions[:sense]).must_be_empty
  _(bot.actions[:combat]).must_be_empty
end

it "queues fire to combat phase" do
  bot = build_bot

  bot.fire(15)

  _(bot.actions[:combat]).must_equal [{ type: :fire, energy: 15 }]
end
```

### Testing Phase Execution Order

When testing that phases execute in the correct order, use integration tests:

```ruby
it "processes sensing before movement" do
  battle = Rubowar::Battle.new([SensingBot, TargetBot], chronon_limit: 2)

  battle.run

  # Verify sensing happened at pre-movement positions
  sensor = battle.arena.actors.find { |r| r.instance.is_a?(SensingBot) }
  _(sensor.instance.sensed_positions).wont_be_empty
end
```

### Testing Phase Isolation

Each phase should be testable in isolation via Arena's `process_action`:

```ruby
it "processes rotate_turret action" do
  arena = build_arena
  actor = build_actor(turret_angle: 0)
  arena.actors = [actor]

  result = arena.process_action(actor: actor, action: { type: :rotate_turret, degrees: 45 })

  _(result).must_equal true
  _(actor.turret_angle).must_equal 45.0
end
```

## Running Tests

```bash
rake test           # Run all tests
ruby test/bullet_test.rb  # Run single test file
```
