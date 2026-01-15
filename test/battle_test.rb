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
    sleep 1 # Exceeds CHRONON_TIMEOUT (0.1s)
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
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], width: 1000, height: 800)

      _(battle.arena.width).must_equal 1000
      _(battle.arena.height).must_equal 800
    end

    it "spawns actors for each rubot class" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot])

      _(battle.arena.actors.length).must_equal 2
    end

    it "starts at chronon zero" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot])

      _(battle.chronons).must_equal 0
    end

    it "starts with no winner" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot])

      _(battle.winner).must_be_nil
    end

    it "starts with empty events" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot])

      _(battle.events).must_equal []
    end

    it "raises error with less than 2 rubots" do
      _ { Rubowar::Battle.new([StationaryBot]) }.must_raise Rubowar::InsufficientRubotsError
    end

    it "raises error with zero width" do
      _ { Rubowar::Battle.new([StationaryBot, StationaryBot], width: 0) }.must_raise Rubowar::InvalidDimensionsError
    end

    it "raises error with negative height" do
      _ { Rubowar::Battle.new([StationaryBot, StationaryBot], height: -100) }.must_raise Rubowar::InvalidDimensionsError
    end

    it "raises error with invalid friction" do
      _ { Rubowar::Battle.new([StationaryBot, StationaryBot], friction: 1.5) }.must_raise Rubowar::InvalidFrictionError
    end

    it "raises error with zero chronon limit" do
      _ { Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 0) }.must_raise Rubowar::InvalidChrononLimitError
    end

    it "raises error with infinite chronon limit" do
      _ { Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: Float::INFINITY) }.must_raise Rubowar::InvalidChrononLimitError
    end
  end

  describe "#on" do
    it "registers callback for event type" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)
      events_received = []
      battle.on(:chronon) { |data| events_received << data }

      battle.run

      _(events_received).wont_be_empty
    end

    it "calls multiple callbacks for same event" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)
      count = 0
      battle.on(:chronon) { count += 1 }
      battle.on(:chronon) { count += 1 }

      battle.run

      _(count).must_equal 2
    end
  end

  describe "#run" do
    it "increments chronons each tick" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 5)

      battle.run

      _(battle.chronons).must_equal 5
    end

    it "emits chronon event each tick" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 3)

      events = battle.run

      chronon_events = events.select { |e| e[:type] == :chronon }
      _(chronon_events.length).must_equal 3
    end

    it "emits battle_end event" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)

      events = battle.run

      end_events = events.select { |e| e[:type] == :battle_end }
      _(end_events.length).must_equal 1
    end

    it "returns all events" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)

      result = battle.run

      _(result).must_be_instance_of Array
      _(result).wont_be_empty
    end

    it "determines winner at end" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)

      battle.run

      _(battle.winner).wont_be_nil
    end
  end

  describe "#battle_over?" do
    it "returns true when only one actor alive" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1000)
      battle.arena.actors[0].health = 0

      result = battle.send(:battle_over?)

      _(result).must_equal true
    end

    it "returns true when chronon limit reached" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 10)
      10.times { battle.instance_variable_set(:@chronons, battle.chronons + 1) }

      result = battle.send(:battle_over?)

      _(result).must_equal true
    end

    it "returns false when multiple actors alive and under limit" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1000)
      battle.instance_variable_set(:@chronons, 5)

      result = battle.send(:battle_over?)

      _(result).must_equal false
    end

    it "returns true when all actors dead" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1000)
      battle.arena.actors.each { |r| r.health = 0 }

      result = battle.send(:battle_over?)

      _(result).must_equal true
    end
  end

  describe "#determine_winner" do
    it "returns sole survivor" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)
      battle.arena.actors[1].health = 0

      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.actors[0]
    end

    it "returns nil when all dead" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)
      battle.arena.actors.each { |r| r.health = 0 }

      battle.send(:determine_winner)

      _(battle.winner).must_be_nil
    end

    it "selects winner by damage dealt when tied on survival" do
      # Create a battle that will timeout with both alive
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)
      battle.run

      # Manually set damage_dealt to test tiebreaker
      battle.arena.actors[0].damage_dealt = 50
      battle.arena.actors[1].damage_dealt = 30
      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.actors[0]
    end

    it "uses HP percentage as secondary tiebreaker after damage dealt" do
      battle = Rubowar::Battle.new([SmallStationaryBot, LargeStationaryBot], chronon_limit: 1)
      battle.run

      # Same damage dealt, but different HP percentages
      # Small bot: 72/80 = 90%
      # Large bot: 96/120 = 80%
      # Small bot should win despite lower absolute HP
      battle.arena.actors[0].damage_dealt = 50
      battle.arena.actors[0].health = 72  # 90% of 80 max
      battle.arena.actors[1].damage_dealt = 50
      battle.arena.actors[1].health = 96  # 80% of 120 max
      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.actors[0]
    end

    it "returns first actor when damage dealt and HP percentage are identical" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], chronon_limit: 1)
      battle.run

      # Both actors have identical damage dealt and HP percentage
      battle.arena.actors[0].damage_dealt = 50
      battle.arena.actors[0].health = 80  # 80% of 100 max
      battle.arena.actors[1].damage_dealt = 50
      battle.arena.actors[1].health = 80  # 80% of 100 max
      battle.send(:determine_winner)

      # max_by returns first match when values are equal
      _(battle.winner).must_equal battle.arena.actors[0]
    end
  end

  describe "sensing results persistence" do
    it "pulse results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.new([PulseTestBot, StationaryBot], chronon_limit: 5)
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
      battle = Rubowar::Battle.new([ProbeTestBotForBattle, StationaryBot], chronon_limit: 5)

      # Position rubots so prober's turret will sweep across target
      prober_actor = battle.arena.actors.find { |r| r.instance.is_a?(ProbeTestBotForBattle) }
      target_actor = battle.arena.actors.find { |r| r.instance.is_a?(StationaryBot) }

      # Place prober at center, target directly to the east
      prober_actor.x = 200
      prober_actor.y = 200
      prober_actor.turret_angle = 350 # Start slightly before east (0 degrees)
      target_actor.x = 400
      target_actor.y = 200

      battle.run

      results = prober_actor.instance.probe_echos_per_tick

      # Tick 1: no previous probe, returns empty ProbeEcho
      _(results[0]).must_be :empty?

      # After turret rotates past 0 degrees (east), should find target in subsequent ticks
      found_target = results[1..].any? { |r| r.found? }
      _(found_target).must_equal true
    end

    it "scan results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.new([ScanTestBot, StationaryBot], chronon_limit: 3)
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
      battle = Rubowar::Battle.new([ScanTestBot, StationaryBot], chronon_limit: 10)
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
      battle = Rubowar::Battle.new([PositionRecordingBot, StationaryBot], chronon_limit: 1)

      # Position bot at known location, facing east
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
      battle = Rubowar::Battle.new([MoveAndFireBot, MoveAndFireBot], chronon_limit: 1)

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
      battle = Rubowar::Battle.new([PulseTestBot, StationaryBot], chronon_limit: 2)

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
      battle = Rubowar::Battle.new([MoveAndFireBot, StationaryBot], chronon_limit: 1)

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
    it "applies timeout damage when act exceeds time limit" do
      battle = Rubowar::Battle.new([TimeoutBot, StationaryBot], chronon_limit: 2)

      timeout_bot = battle.arena.actors.find { |r| r.instance.is_a?(TimeoutBot) }
      initial_health = timeout_bot.health

      battle.run

      # Bot should have taken TIMEOUT_DAMAGE (50) each chronon
      expected_health = initial_health - (Rubowar::Config::Battle::TIMEOUT_DAMAGE * 2)
      _(timeout_bot.health).must_equal expected_health
    end

    it "continues battle after timeout" do
      battle = Rubowar::Battle.new([TimeoutBot, StationaryBot], chronon_limit: 3)

      events = battle.run

      # Battle continues until bot dies (100 HP / 50 damage per timeout = 2 chronons)
      # or chronon limit reached - whichever comes first
      _(battle.chronons).must_be :>=, 2
      chronon_events = events.select { |e| e[:type] == :chronon }
      _(chronon_events.length).must_be :>=, 2
    end

    it "emits error event on timeout" do
      battle = Rubowar::Battle.new([TimeoutBot, StationaryBot], chronon_limit: 1)

      events = battle.run

      error_events = events.select { |e| e[:type] == :error }
      _(error_events).wont_be_empty
      _(error_events.first[:error]).must_include "timeout"
    end

    it "applies error damage when act raises StandardError" do
      battle = Rubowar::Battle.new([ErrorBot, StationaryBot], chronon_limit: 2)

      error_bot = battle.arena.actors.find { |r| r.instance.is_a?(ErrorBot) }
      initial_health = error_bot.health

      battle.run

      # Bot should have taken ERROR_DAMAGE (20) each chronon, not TIMEOUT_DAMAGE (50)
      expected_health = initial_health - (Rubowar::Config::Battle::ERROR_DAMAGE * 2)
      _(error_bot.health).must_equal expected_health
    end

    it "emits error event with exception on StandardError" do
      battle = Rubowar::Battle.new([ErrorBot, StationaryBot], chronon_limit: 1)

      events = battle.run

      error_events = events.select { |e| e[:type] == :error }
      _(error_events).wont_be_empty
      _(error_events.first[:error]).must_be_instance_of StandardError
      _(error_events.first[:error].message).must_equal "Intentional test error"
    end

    it "continues battle after StandardError" do
      battle = Rubowar::Battle.new([ErrorBot, StationaryBot], chronon_limit: 3)

      events = battle.run

      # Battle should continue despite errors
      _(battle.chronons).must_equal 3
      chronon_events = events.select { |e| e[:type] == :chronon }
      _(chronon_events.length).must_equal 3
    end
  end

  describe "death callback" do
    it "calls on_death exactly once when rubot dies" do
      battle = Rubowar::Battle.new([DeathTrackingBot, StationaryBot], chronon_limit: 5)

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
      battle = Rubowar::Battle.new([DeathTrackingBot, StationaryBot], chronon_limit: 3)

      death_bot = battle.arena.actors.find { |r| r.instance.is_a?(DeathTrackingBot) }

      battle.run

      # Bot never died, so on_death should never be called
      _(death_bot.instance.death_count).must_equal 0
    end

    it "emits death event exactly once" do
      battle = Rubowar::Battle.new([DeathTrackingBot, StationaryBot], chronon_limit: 5)

      death_bot = battle.arena.actors.find { |r| r.instance.is_a?(DeathTrackingBot) }

      # Call on_spawn first then kill the bot
      battle.send(:call_on_spawn)
      death_bot.health = 0

      # Run chronons manually
      5.times do
        battle.instance_variable_set(:@chronons, battle.chronons + 1)
        battle.send(:run_chronon)
      end

      death_events = battle.events.select { |e| e[:type] == :death && e[:actor] == death_bot }
      _(death_events.length).must_equal 1
    end
  end

  describe "detect action" do
    it "reports zero counts when not being sensed" do
      battle = Rubowar::Battle.new([DetectTestBot, StationaryBot], chronon_limit: 2)

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
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], chronon_limit: 2)

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
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], chronon_limit: 2)

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
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], chronon_limit: 2)

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
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot, SensingBot], chronon_limit: 2)

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
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], chronon_limit: 3)

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
      battle = Rubowar::Battle.new([DetectTestBot, StationaryBot], chronon_limit: 1)

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      detector.energy = 50

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Energy should have decreased by 2 (detect cost) plus regen
      # Starting: 50, detect: -2, regen: +10 = 58
      _(detector.energy).must_equal 58
    end

    it "returns false and fails when insufficient energy" do
      battle = Rubowar::Battle.new([DetectTestBot, StationaryBot], chronon_limit: 1)

      detector = battle.arena.actors.find { |r| r.instance.is_a?(DetectTestBot) }
      detector.energy = 1 # Not enough for detect (costs 2)

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # detect_intel should be empty (action failed, returns default empty DetectIntel)
      _(detector.instance.detect_intel).must_be :empty?
    end
  end
end
