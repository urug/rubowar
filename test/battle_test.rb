# frozen_string_literal: true

require "test_helper"

# Test bot that moves and fires to test phased action processing
class MoveAndFireBot
  include Rubowar::Rubot

  size :medium

  attr_accessor :move_angle, :should_fire

  def on_spawn
    @move_angle = 0
    @should_fire = true
  end

  def act
    thrust(speed: 5, angle: @move_angle)
    fire(10) if @should_fire
  end
end

# Test bot that records its position when firing
class PositionRecordingBot
  include Rubowar::Rubot

  size :medium

  attr_reader :position_when_fired, :position_at_tick_start

  def on_spawn
    @position_when_fired = nil
    @position_at_tick_start = nil
  end

  def act
    @position_at_tick_start = { x:, y: }
    thrust(speed: 10, angle: 0) # Move east
    fire(10)
  end
end

# Test bot that stores pulse results each tick
class PulseTestBot
  include Rubowar::Rubot

  size :medium

  attr_reader :pulse_echos_per_tick

  def on_spawn
    @pulse_echos_per_tick = []
  end

  def act
    # Read previous tick's result, then queue new pulse
    @pulse_echos_per_tick << (pulse_echo&.dup || [])
    pulse(distance: 800)
  end
end

# Test bot that stores probe results each tick
class ProbeTestBotForBattle
  include Rubowar::Rubot

  size :medium

  attr_reader :probe_echos_per_tick

  def on_spawn
    @probe_echos_per_tick = []
  end

  def act
    # Read previous tick's result, then queue new probe
    @probe_echos_per_tick << probe_echo&.dup
    probe(:size)
    # Rotate turret to sweep for targets
    rotate_turret(15)
  end
end

# Test bot that stores scan results each tick
class ScanTestBot
  include Rubowar::Rubot

  size :medium

  attr_reader :scan_echos_per_tick

  def on_spawn
    @scan_echos_per_tick = []
  end

  def act
    # Read previous tick's result, then queue new scan
    @scan_echos_per_tick << (scan_echo&.dup || [])
    scan(angle: 360, distance: 500)
  end
end

# Stationary target bot
class StationaryBot
  include Rubowar::Rubot

  size :medium
  def act; end
end

# Bot that times out (infinite loop in act)
class TimeoutBot
  include Rubowar::Rubot

  size :medium

  attr_reader :ticks_executed

  def on_spawn
    @ticks_executed = 0
  end

  def act
    @ticks_executed += 1
    sleep(Rubowar::Config::Battle::CHRONON_DEADLINE + 0.2) # Exceeds deadline - bot will skip actions
  end
end

# Bot that raises a StandardError (not Timeout)
class ErrorBot
  include Rubowar::Rubot

  size :medium

  def act
    raise StandardError, "Intentional test error"
  end
end

# Bot that tracks on_death calls
class DeathTrackingBot
  include Rubowar::Rubot

  size :medium

  attr_reader :death_count

  def on_spawn
    @death_count = 0
  end

  def on_death
    @death_count += 1
  end

  def act; end
end

class SmallStationaryBot
  include Rubowar::Rubot

  size :small
  def act; end
end

class LargeStationaryBot
  include Rubowar::Rubot

  size :large
  def act; end
end

# Test bot that detects if it's being sensed
class DetectTestBot
  include Rubowar::Rubot

  size :medium

  attr_reader :detect_intels_per_tick

  def on_spawn
    @detect_intels_per_tick = []
  end

  def act
    # Record detect result from current tick's sense phase
    @detect_intels_per_tick << detect_intel&.dup
    detect
  end
end

# Test bot that actively senses a target
class SensingBot
  include Rubowar::Rubot

  size :medium

  attr_accessor :do_probe, :do_scan, :do_pulse

  def on_spawn
    @do_probe = false
    @do_scan = false
    @do_pulse = false
  end

  def act
    probe(:size) if @do_probe
    scan(angle: 360, distance: 500) if @do_scan
    pulse(distance: 500) if @do_pulse
  end
end

describe Rubowar::Battle do
  describe "initialization" do
    it "creates arena with specified dimensions" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], width: 1000, height: 800)

      _(battle.arena.width).must_equal 1000
      _(battle.arena.height).must_equal 800
    end

    it "registers actors for each rubot class" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot])

      _(battle.registered_actors.length).must_equal 2
    end

    it "starts at chronon zero" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot])

      _(battle.chronon).must_equal 0
    end

    it "starts with no winner" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot])

      _(battle.winner).must_be_nil
    end

    it "starts with empty events" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot])

      _(battle.event_log).must_equal []
    end

    it "raises error with less than 2 rubots when run" do
      battle = Rubowar::Battle.local([StationaryBot])
      _ { battle.run }.must_raise Rubowar::InsufficientRubotsError
    end

    it "raises error with zero chronon limit" do
      _ { Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 0) }.must_raise Rubowar::InvalidChrononLimitError
    end

    it "raises error with infinite chronon limit" do
      _ { Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: Float::INFINITY) }.must_raise Rubowar::InvalidChrononLimitError
    end
  end

  describe "#on" do
    it "registers callback for event type" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 1)
      events_received = []
      battle.on(:chronon) { |data| events_received << data }

      battle.run

      _(events_received).wont_be_empty
    end

    it "calls multiple callbacks for same event" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 1)
      count = 0
      battle.on(:chronon) { count += 1 }
      battle.on(:chronon) { count += 1 }

      battle.run

      _(count).must_equal 2
    end
  end

  describe "#run" do
    it "increments chronons each tick" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 5)

      battle.run

      _(battle.chronon).must_equal 5
    end

    it "emits chronon event each tick" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 3)

      events = battle.run

      chronon_events = events.select { |e| e[:type] == :chronon }
      _(chronon_events.length).must_equal 3
    end

    it "emits battle_end event" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 1)

      events = battle.run

      end_events = events.select { |e| e[:type] == :battle_end }
      _(end_events.length).must_equal 1
    end

    it "returns all events" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 1)

      result = battle.run

      _(result).must_be_kind_of Array
      _(result).wont_be_empty
    end

    it "determines winner at end" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 1)

      battle.run

      _(battle.winner).wont_be_nil
    end
  end

  describe "sensing results persistence" do
    it "pulse results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.local([PulseTestBot, StationaryBot], chronon_limit: 5)
      battle.run

      pulser = battle.arena.actors.find { |r| r.instance.is_a?(PulseTestBot) }
      results = pulser.instance.pulse_echos_per_tick

      # Tick 1: no previous pulse, returns empty PulseEcho
      _(results[0]).must_be :empty?

      # Tick 2+: should have results from previous tick's pulse (if target in range)
      # At least one tick after the first should have found the target
      found_target = results[1..].any? { |r| r.any? { |t| t[:type] == :rubot } }
      _(found_target).must_equal true
    end

    it "probe results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.local([ProbeTestBotForBattle, StationaryBot], chronon_limit: 5)
      battle.spawn_rubots

      # Position rubots so prober's turret will sweep across target
      prober_actor = battle.arena.actors.find { |r| r.instance.is_a?(ProbeTestBotForBattle) }
      target_actor = battle.arena.actors.find { |r| r.instance.is_a?(StationaryBot) }

      # Place prober at center, target directly to the east
      prober_actor.x = 200
      prober_actor.y = 200
      # Start at 345 so after 15 degree rotation, turret is at 0 (pointing at target)
      prober_actor.turret_angle = 345
      target_actor.x = 400
      target_actor.y = 200

      battle.run

      results = prober_actor.instance.probe_echos_per_tick

      # Tick 1: no previous probe, returns empty ProbeEcho
      _(results[0]).must_be :empty?

      # After turret rotates to 0 degrees (east), should find target in subsequent ticks
      found_target = results[1..].any?(&:found?)
      _(found_target).must_equal true
    end

    it "scan results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.local([ScanTestBot, StationaryBot], chronon_limit: 3)
      battle.run

      scanner = battle.arena.actors.find { |r| r.instance.is_a?(ScanTestBot) }
      results = scanner.instance.scan_echos_per_tick

      # Tick 1: no previous scan, returns empty ScanEcho
      _(results[0]).must_be :empty?

      # Tick 2+: should have results from previous tick (360 degree scan finds everything)
      _(results[1]).wont_be_empty
      _(results[1].any? { |t| t[:type] == :rubot }).must_equal true
    end

    it "sensing results are not cleared before rubot tick runs" do
      # This test specifically verifies the bug fix where results were cleared
      # in setup_rubot_for_tick before the rubot could read them
      battle = Rubowar::Battle.local([ScanTestBot, StationaryBot], chronon_limit: 10)
      battle.run

      scanner = battle.arena.actors.find { |r| r.instance.is_a?(ScanTestBot) }
      results = scanner.instance.scan_echos_per_tick

      # Count how many ticks found the target (should be all ticks after the first)
      ticks_with_target = results[1..].count { |r| r.any? { |t| t[:type] == :rubot } }

      # All ticks after the first should have found the target with 360 degree scan
      _(ticks_with_target).must_equal results.length - 1
    end
  end

  describe "phased action processing" do
    it "fires bullets from post-movement position" do
      battle = Rubowar::Battle.local([PositionRecordingBot, StationaryBot], chronon_limit: 1)

      # Spawn actors first, then position at known location
      battle.spawn_rubots
      mover = battle.arena.actors.find { |r| r.instance.is_a?(PositionRecordingBot) }
      mover.x = 100.0
      mover.y = 300.0
      mover.turret_angle = 0 # Facing east

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Bot thrusted east at speed 10, so it moved ~10 pixels east
      # Bullet should spawn from the NEW position, not the old one
      bullet = battle.arena.bullets.first
      _(bullet).wont_be_nil

      # Bullet x should be greater than starting x (100) + radius
      # because bot moved east before firing
      _(bullet.x).must_be :>, 100 + mover.radius
    end

    it "processes all rubots movement before any rubot fires" do
      battle = Rubowar::Battle.local([MoveAndFireBot, MoveAndFireBot], chronon_limit: 1)
      battle.spawn_rubots

      # Position both bots
      bot_a = battle.arena.actors[0]
      bot_b = battle.arena.actors[1]

      bot_a.x = 100.0
      bot_a.y = 300.0
      bot_a.turret_angle = 90  # Turret points north

      bot_b.x = 200.0
      bot_b.y = 300.0
      bot_b.turret_angle = 90  # Turret points north

      battle.send(:call_on_spawn)

      # Set move_angle AFTER on_spawn (which resets it to 0)
      bot_a.instance.move_angle = 90 # Move north
      bot_b.instance.move_angle = 90 # Also move north

      battle.send(:run_chronon)

      # Both bots should have moved north before firing
      # Their bullets should spawn from y > 300 (moved north)
      bullets = battle.arena.bullets
      _(bullets.length).must_equal 2
      _(bullets.all? { |b| b.y > 300 }).must_equal true
    end

    it "processes sensing before movement" do
      # Create a battle where pulse happens before movement
      battle = Rubowar::Battle.local([PulseTestBot, StationaryBot], chronon_limit: 2)
      battle.spawn_rubots

      pulser = battle.arena.actors.find { |r| r.instance.is_a?(PulseTestBot) }
      target = battle.arena.actors.find { |r| r.instance.is_a?(StationaryBot) }

      # Position them close together
      pulser.x = 200.0
      pulser.y = 300.0
      target.x = 250.0
      target.y = 300.0

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)
      battle.send(:run_chronon)

      # Pulse from tick 1 should detect target at its pre-movement position
      results = pulser.instance.pulse_echos_per_tick
      _(results[1]).wont_be_empty
    end

    it "deducts sensing energy before combat energy" do
      # If a bot queues fire() then pulse(), pulse should still execute first
      # and use energy first, potentially leaving less for fire
      battle = Rubowar::Battle.local([MoveAndFireBot, StationaryBot], chronon_limit: 1)
      battle.spawn_rubots

      bot = battle.arena.actors.find { |r| r.instance.is_a?(MoveAndFireBot) }
      bot.x = 400.0
      bot.y = 300.0
      bot.energy = 15 # Only enough for fire(10) OR pulse, not both

      # Redefine act to fire first, then pulse
      bot.instance.define_singleton_method(:act) do
        fire(10) # Queued first in code
        pulse(distance: 100) # Queued second, but processed first!
        thrust(speed: 1, angle: 0)
      end

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Pulse costs ~4 energy (2 base + 100/75 ceil = 4)
      # Fire costs 10 energy
      # With 15 energy: pulse takes 4, leaving 11 for fire - should succeed
      # But if fire went first: fire takes 10, leaving 5 for pulse
      # The pulse result being set proves pulse executed
      _(bot.instance.pulse_echo).wont_be_nil
    end
  end

  describe "error handling" do
    it "slow rubots take no damage and skip actions" do
      battle = Rubowar::Battle.local([TimeoutBot, StationaryBot], chronon_limit: 2)

      timeout_bot = battle.registered_actors.find { |r| r.instance.is_a?(TimeoutBot) }
      initial_health = timeout_bot.health

      battle.run

      # Slow bots take no damage - they just skip their actions
      _(timeout_bot.health).must_equal initial_health
    end

    it "continues battle when rubots are slow" do
      battle = Rubowar::Battle.local([TimeoutBot, StationaryBot], chronon_limit: 3)

      events = battle.run

      # Battle continues to chronon limit (slow bots don't die from being slow)
      _(battle.chronon).must_equal 3
      chronon_events = events.select { |e| e[:type] == :chronon }
      _(chronon_events.length).must_equal 3
    end

    it "does not emit error event for slow rubots" do
      battle = Rubowar::Battle.local([TimeoutBot, StationaryBot], chronon_limit: 1)

      events = battle.run

      # Slow rubots don't cause errors - they just skip their actions
      error_events = events.select { |e| e[:type] == :error }
      _(error_events).must_be_empty
    end

    it "applies error damage when act raises StandardError" do
      battle = Rubowar::Battle.local([ErrorBot, StationaryBot], chronon_limit: 2)

      error_bot = battle.registered_actors.find { |r| r.instance.is_a?(ErrorBot) }
      initial_health = error_bot.health

      battle.run

      # Bot should have taken ERROR_DAMAGE (20) each chronon
      expected_health = initial_health - (Rubowar::Config::Battle::ERROR_DAMAGE * 2)
      _(error_bot.health).must_equal expected_health
    end

    it "emits error event with exception on StandardError" do
      battle = Rubowar::Battle.local([ErrorBot, StationaryBot], chronon_limit: 1)

      events = battle.run

      error_events = events.select { |e| e[:type] == :error }
      _(error_events).wont_be_empty
      _(error_events.first[:error]).must_be_instance_of StandardError
      _(error_events.first[:error].message).must_equal "Intentional test error"
    end

    it "continues battle after StandardError" do
      battle = Rubowar::Battle.local([ErrorBot, StationaryBot], chronon_limit: 3)

      events = battle.run

      # Battle should continue despite errors
      _(battle.chronon).must_equal 3
      chronon_events = events.select { |e| e[:type] == :chronon }
      _(chronon_events.length).must_equal 3
    end
  end

  describe "death callback" do
    it "calls on_death exactly once when rubot dies" do
      battle = Rubowar::Battle.local([DeathTrackingBot, StationaryBot], chronon_limit: 5)
      battle.spawn_rubots

      death_bot = battle.arena.actors.find { |r| r.instance.is_a?(DeathTrackingBot) }

      # Call on_spawn first to initialize the bot (sets @death_count = 0)
      battle.send(:call_on_spawn)

      # Now kill the bot after initialization
      death_bot.health = 0

      # Run remaining chronons
      5.times { battle.send(:run_chronon) }

      # on_death should be called exactly once, not every chronon
      _(death_bot.instance.death_count).must_equal 1
    end

    it "does not call on_death for alive rubots" do
      battle = Rubowar::Battle.local([DeathTrackingBot, StationaryBot], chronon_limit: 3)

      death_bot = battle.registered_actors.find { |r| r.instance.is_a?(DeathTrackingBot) }

      battle.run

      # Bot never died, so on_death should never be called
      _(death_bot.instance.death_count).must_equal 0
    end

    it "emits death event exactly once" do
      battle = Rubowar::Battle.local([DeathTrackingBot, StationaryBot], chronon_limit: 5)
      battle.spawn_rubots

      death_bot = battle.arena.actors.find { |r| r.instance.is_a?(DeathTrackingBot) }

      # Call on_spawn first then kill the bot
      battle.send(:call_on_spawn)
      death_bot.health = 0

      # Run chronons manually
      5.times do
        battle.event_bus.increment_chronon
        battle.send(:run_chronon)
      end

      death_events = battle.event_log.select { |e| e[:type] == :death && e[:actor_id] == death_bot.id }
      _(death_events.length).must_equal 1
    end
  end

  describe "detect action" do
    it "reports zero counts when not being sensed" do
      battle = Rubowar::Battle.local([DetectTestBot, StationaryBot], chronon_limit: 2)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      target = battle.arena.actors.find { |r| r.instance.is_a?(StationaryBot) }

      # Position them far apart so no sensing happens
      detector.x = 100.0
      detector.y = 100.0
      target.x = 500.0
      target.y = 500.0

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # After first tick, detect_intel should show zero counts
      result = detector.instance.detect_intel
      _(result).wont_be_nil
      _(result[:probed]).must_equal 0
      _(result[:scanned]).must_equal 0
      _(result[:pulsed]).must_equal 0
    end

    it "reports probe count when probed" do
      battle = Rubowar::Battle.local([DetectTestBot, SensingBot], chronon_limit: 2)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.actors.find { |r| r.instance.is_a?(SensingBot) }

      # Position sensor to aim at detector
      sensor.x = 100.0
      sensor.y = 300.0
      sensor.turret_angle = 0 # Facing east
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_probe = true # Set AFTER on_spawn resets it
      battle.send(:run_chronon)

      # Detector should report being probed
      result = detector.instance.detect_intel
      _(result[:probed]).must_equal 1
      _(result[:scanned]).must_equal 0
      _(result[:pulsed]).must_equal 0
    end

    it "reports scan count when scanned" do
      battle = Rubowar::Battle.local([DetectTestBot, SensingBot], chronon_limit: 2)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.actors.find { |r| r.instance.is_a?(SensingBot) }

      # Position them close enough for scan
      sensor.x = 100.0
      sensor.y = 300.0
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_scan = true # Set AFTER on_spawn resets it
      battle.send(:run_chronon)

      # Detector should report being scanned
      result = detector.instance.detect_intel
      _(result[:probed]).must_equal 0
      _(result[:scanned]).must_equal 1
      _(result[:pulsed]).must_equal 0
    end

    it "reports pulse count when pulsed" do
      battle = Rubowar::Battle.local([DetectTestBot, SensingBot], chronon_limit: 2)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.actors.find { |r| r.instance.is_a?(SensingBot) }

      # Position them close enough for pulse
      sensor.x = 100.0
      sensor.y = 300.0
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_pulse = true # Set AFTER on_spawn resets it
      battle.send(:run_chronon)

      # Detector should report being pulsed
      result = detector.instance.detect_intel
      _(result[:probed]).must_equal 0
      _(result[:scanned]).must_equal 0
      _(result[:pulsed]).must_equal 1
    end

    it "reports combined counts from multiple sensors" do
      battle = Rubowar::Battle.local([DetectTestBot, SensingBot, SensingBot], chronon_limit: 2)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      sensors = battle.arena.actors.select { |r| r.instance.is_a?(SensingBot) }

      # Position all close together
      detector.x = 200.0
      detector.y = 300.0
      sensors[0].x = 100.0
      sensors[0].y = 300.0
      sensors[1].x = 300.0
      sensors[1].y = 300.0

      battle.send(:call_on_spawn)
      # Both sensors pulse - set AFTER on_spawn resets them
      sensors[0].instance.do_pulse = true
      sensors[1].instance.do_pulse = true
      battle.send(:run_chronon)

      # Detector should report being pulsed twice
      result = detector.instance.detect_intel
      _(result[:pulsed]).must_equal 2
    end

    it "resets counts each tick" do
      battle = Rubowar::Battle.local([DetectTestBot, SensingBot], chronon_limit: 3)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.actors.find { |r| r.instance.is_a?(SensingBot) }

      # Position them close
      sensor.x = 100.0
      sensor.y = 300.0
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_pulse = true # Set AFTER on_spawn resets it
      battle.send(:run_chronon)

      # First tick: pulsed
      _(detector.instance.detect_intel[:pulsed]).must_equal 1

      # Stop pulsing
      sensor.instance.do_pulse = false
      battle.send(:run_chronon)

      # Second tick: not pulsed (counts reset)
      _(detector.instance.detect_intel[:pulsed]).must_equal 0
    end

    it "costs 2 energy" do
      battle = Rubowar::Battle.local([DetectTestBot, StationaryBot], chronon_limit: 1)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      detector.energy = 50

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Energy should have decreased by 2 (detect cost) plus regen
      # Starting: 50, detect: -2, regen: +energy_regen
      _(detector.energy).must_equal 50 - 2 + detector.energy_regen
    end

    it "returns false and fails when insufficient energy" do
      battle = Rubowar::Battle.local([DetectTestBot, StationaryBot], chronon_limit: 1)
      battle.spawn_rubots

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      detector.energy = 1 # Not enough for detect (costs 2)

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # detect_intel should be empty (action failed, returns default empty DetectIntel)
      _(detector.instance.detect_intel).must_be :empty?
    end
  end

  describe "actor interface requirements" do
    it "requires _act_completed accessor for deadline tracking" do
      actor = Rubowar::LocalActor.new(StationaryBot)

      _(actor).must_respond_to :_act_completed
      _(actor).must_respond_to :_act_completed=
      _(actor._act_completed).must_equal false
    end

    it "requires reset_actions method" do
      actor = Rubowar::LocalActor.new(StationaryBot)

      _(actor).must_respond_to :reset_actions
      actor.reset_actions
      _(actor.rubot_actions).must_equal({ sense: [], move: [], combat: [] })
    end

    it "requires rubot_actions returning phased action hash" do
      actor = Rubowar::LocalActor.new(StationaryBot)
      actor.reset_actions

      actions = actor.rubot_actions
      _(actions).must_be_kind_of Hash
      _(actions.keys).must_include :sense
      _(actions.keys).must_include :move
      _(actions.keys).must_include :combat
    end

    it "requires alive? and dead? methods" do
      actor = Rubowar::LocalActor.new(StationaryBot)

      _(actor.alive?).must_equal true
      _(actor.dead?).must_equal false

      actor.health = 0

      _(actor.alive?).must_equal false
      _(actor.dead?).must_equal true
    end

    it "requires id for tracking" do
      actor = Rubowar::LocalActor.new(StationaryBot)

      _(actor.id).must_match(/^rbot-[0-9a-f]{8}$/)
    end

    it "requires to_state returning RubotState" do
      actor = Rubowar::LocalActor.new(StationaryBot)

      state = actor.to_state
      _(state).must_be_instance_of Rubowar::RubotState
    end

    it "requires state setters for chronon setup" do
      actor = Rubowar::LocalActor.new(StationaryBot)

      _(actor).must_respond_to :rubot_state=
      _(actor).must_respond_to :arena_state=
      _(actor).must_respond_to :_pending_energy_spend=
    end
  end

  describe "stub actor compatibility" do
    it "runs battle with stub actors" do
      event_bus = Rubowar::EventBus.new(chronon_limit: 5)
      arena = Rubowar::Arena.new(width: 640, height: 640, event_bus:)
      battle = Rubowar::Battle.new(arena:, event_bus:)

      stub1 = Rubowar::BasicActor.new(size: :medium)
      stub2 = Rubowar::BasicActor.new(size: :medium)
      battle.register(stub1)
      battle.register(stub2)

      events = battle.run

      _(battle.chronon).must_equal 5
      _(events).wont_be_empty
    end

    it "processes pre-set thrust actions on stub actor" do
      event_bus = Rubowar::EventBus.new(chronon_limit: 1)
      arena = Rubowar::Arena.new(width: 640, height: 640, event_bus:)
      battle = Rubowar::Battle.new(arena:, event_bus:)

      stub1 = Rubowar::BasicActor.new(size: :medium)
      stub2 = Rubowar::BasicActor.new(size: :medium)
      battle.register(stub1)
      battle.register(stub2)

      battle.spawn_rubots
      initial_x = stub1.x

      # Override act to set actions (simulates remote client pushing actions during act phase)
      stub1.define_singleton_method(:act) do
        set_actions(move: [{ type: :thrust, speed: 5, angle: 0 }])
      end

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Stub should have moved east
      _(stub1.x).must_be :>, initial_x
    end

    it "works alongside RubotActor" do
      event_bus = Rubowar::EventBus.new(chronon_limit: 3)
      arena = Rubowar::Arena.new(width: 640, height: 640, event_bus:)
      battle = Rubowar::Battle.new(arena:, event_bus:)

      stub = Rubowar::BasicActor.new(size: :medium)
      rubot_actor = Rubowar::LocalActor.new(StationaryBot)

      battle.register(stub)
      battle.register(rubot_actor)

      battle.run

      _(battle.chronon).must_equal 3
      _(battle.arena.actors.length).must_equal 2
    end

    it "stub actor has same interface as RubotActor" do
      rubot = Rubowar::LocalActor.new(StationaryBot)
      stub = Rubowar::BasicActor.new(size: :medium)

      # Core interface methods Battle depends on
      interface_methods = %i[
        id x y velocity_x velocity_y turret_angle
        health energy shield_level damage_dealt damage_taken
        death_processed _act_completed alive? dead?
        to_state rubot_actions reset_actions act
        rubot_state= arena_state= _pending_energy_spend=
        apply_damage spend_energy radius
      ]

      interface_methods.each do |method|
        _(rubot).must_respond_to method, "RubotActor missing #{method}"
        _(stub).must_respond_to method, "BasicActor missing #{method}"
      end
    end
  end

  describe "deadline behavior" do
    it "skips actions for slow rubots that exceed deadline" do
      battle = Rubowar::Battle.local([TimeoutBot, StationaryBot], chronon_limit: 1)
      battle.spawn_rubots

      timeout_bot = battle.arena.actors.find { |r| r.instance.is_a?(TimeoutBot) }
      initial_x = timeout_bot.x

      # Manually inject a thrust action before running
      # TimeoutBot will sleep in act(), so actions should be cleared
      timeout_bot.instance.define_singleton_method(:act) do
        thrust(speed: 10, angle: 0)
        sleep(Rubowar::Config::Battle::CHRONON_DEADLINE + 0.2)
      end

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Position should be unchanged - actions were cleared due to timeout
      _(timeout_bot.x).must_be_within_delta initial_x, 1.0
    end

    it "clears _act_completed flag at start of each chronon" do
      battle = Rubowar::Battle.local([StationaryBot, StationaryBot], chronon_limit: 2)
      battle.spawn_rubots

      actor = battle.arena.actors.first
      actor._act_completed = true

      battle.send(:call_on_spawn)
      # setup_rubot_for_chronon is called at start of run_chronon
      battle.send(:run_chronon)

      # After chronon, flag should be true (act completed)
      _(actor._act_completed).must_equal true

      # Manually call setup to see it clears the flag
      battle.send(:setup_rubot_for_chronon, actor)
      _(actor._act_completed).must_equal false
    end

    it "handles multiple slow rubots without crashing" do
      battle = Rubowar::Battle.local([TimeoutBot, TimeoutBot], chronon_limit: 2)

      events = battle.run

      _(battle.chronon).must_equal 2
      _(events).wont_be_empty
    end

    it "processes fast rubots even when slow rubot times out" do
      battle = Rubowar::Battle.local([TimeoutBot, MoveAndFireBot], chronon_limit: 1)
      battle.spawn_rubots

      fast_bot = battle.arena.actors.find { |r| r.instance.is_a?(MoveAndFireBot) }
      initial_x = fast_bot.x

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Fast bot should have moved (thrust east at speed 5)
      _(fast_bot.x).must_be :>, initial_x
    end

    it "maintains state consistency after deadline" do
      battle = Rubowar::Battle.local([TimeoutBot, StationaryBot], chronon_limit: 2)

      timeout_bot = battle.registered_actors.find { |r| r.instance.is_a?(TimeoutBot) }
      initial_health = timeout_bot.health
      timeout_bot.energy = 50

      battle.run

      # Health unchanged (no damage for slowness)
      _(timeout_bot.health).must_equal initial_health

      # Energy regenerated normally (energy_regen/tick, 2 ticks, capped at max_energy)
      _(timeout_bot.energy).must_equal [50 + (timeout_bot.energy_regen * 2), timeout_bot.max_energy].min
    end
  end
end
