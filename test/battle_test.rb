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

  def tick
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

  def tick
    @position_at_tick_start = { x: x, y: y }
    thrust(speed: 10, angle: 0) # Move east
    fire(10)
  end
end

# Test bot that stores pulse results each tick
class PulseTestBot
  include Rubowar::Rubot
  size :medium

  attr_reader :pulse_results_per_tick

  def on_spawn
    @pulse_results_per_tick = []
  end

  def tick
    # Read previous tick's result, then queue new pulse
    @pulse_results_per_tick << (pulse_result&.dup || [])
    pulse(distance: 800)
  end
end

# Test bot that stores probe results each tick
class ProbeTestBotForBattle
  include Rubowar::Rubot
  size :medium

  attr_reader :probe_results_per_tick

  def on_spawn
    @probe_results_per_tick = []
  end

  def tick
    # Read previous tick's result, then queue new probe
    @probe_results_per_tick << probe_result&.dup
    probe(:size)
    # Rotate turret to sweep for targets
    turret(15)
  end
end

# Test bot that stores scan results each tick
class ScanTestBot
  include Rubowar::Rubot
  size :medium

  attr_reader :scan_results_per_tick

  def on_spawn
    @scan_results_per_tick = []
  end

  def tick
    # Read previous tick's result, then queue new scan
    @scan_results_per_tick << (scan_result&.dup || [])
    scan(angle: 360, distance: 500)
  end
end

# Stationary target bot
class StationaryBot
  include Rubowar::Rubot
  size :medium
  def tick; end
end

# Test bot that detects if it's being sensed
class DetectTestBot
  include Rubowar::Rubot
  size :medium

  attr_reader :detect_results_per_tick

  def on_spawn
    @detect_results_per_tick = []
  end

  def tick
    # Record detect result from current tick's sense phase
    @detect_results_per_tick << detect_result&.dup
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

  def tick
    probe(:size) if @do_probe
    scan(angle: 360, distance: 500) if @do_scan
    pulse(distance: 500) if @do_pulse
  end
end

describe Rubowar::Battle do
  describe "sensing results persistence" do
    it "pulse results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.new([PulseTestBot, StationaryBot], tick_limit: 5)
      battle.run

      pulser = battle.arena.runners.find { |r| r.instance.is_a?(PulseTestBot) }
      results = pulser.instance.pulse_results_per_tick

      # Tick 1: no previous pulse, returns []
      _(results[0]).must_equal []

      # Tick 2+: should have results from previous tick's pulse (if target in range)
      # At least one tick after the first should have found the target
      found_target = results[1..].any? { |r| r.any? { |t| t[:type] == :rubot } }
      _(found_target).must_equal true
    end

    it "probe results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.new([ProbeTestBotForBattle, StationaryBot], tick_limit: 5)

      # Position robots so prober's turret will sweep across target
      prober_runner = battle.arena.runners.find { |r| r.instance.is_a?(ProbeTestBotForBattle) }
      target_runner = battle.arena.runners.find { |r| r.instance.is_a?(StationaryBot) }

      # Place prober at center, target directly to the east
      prober_runner.x = 200
      prober_runner.y = 200
      prober_runner.turret_angle = 350 # Start slightly before east (0 degrees)
      target_runner.x = 400
      target_runner.y = 200

      battle.run

      results = prober_runner.instance.probe_results_per_tick

      # Tick 1: no previous probe, returns nil
      _(results[0]).must_be_nil

      # After turret rotates past 0 degrees (east), should find target in subsequent ticks
      found_target = results[1..].any? { |r| r&.key?(:size) }
      _(found_target).must_equal true
    end

    it "scan results from tick N are available in tick N+1" do
      battle = Rubowar::Battle.new([ScanTestBot, StationaryBot], tick_limit: 3)
      battle.run

      scanner = battle.arena.runners.find { |r| r.instance.is_a?(ScanTestBot) }
      results = scanner.instance.scan_results_per_tick

      # Tick 1: no previous scan, returns []
      _(results[0]).must_equal []

      # Tick 2+: should have results from previous tick (360 degree scan finds everything)
      _(results[1]).wont_be_empty
      _(results[1].any? { |t| t[:type] == :rubot }).must_equal true
    end

    it "sensing results are not cleared before rubot tick runs" do
      # This test specifically verifies the bug fix where results were cleared
      # in setup_rubot_for_tick before the rubot could read them
      battle = Rubowar::Battle.new([ScanTestBot, StationaryBot], tick_limit: 10)
      battle.run

      scanner = battle.arena.runners.find { |r| r.instance.is_a?(ScanTestBot) }
      results = scanner.instance.scan_results_per_tick

      # Count how many ticks found the target (should be all ticks after the first)
      ticks_with_target = results[1..].count { |r| r.any? { |t| t[:type] == :rubot } }

      # All ticks after the first should have found the target with 360 degree scan
      _(ticks_with_target).must_equal results.length - 1
    end
  end

  describe "#determine_winner" do
    it "selects winner by damage dealt when tied on survival" do
      # Create a battle that will timeout with both alive
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], tick_limit: 1)
      battle.run

      # Manually set damage_dealt to test tiebreaker
      battle.arena.runners[0].damage_dealt = 50
      battle.arena.runners[1].damage_dealt = 30
      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.runners[0]
    end

    it "uses HP as secondary tiebreaker after damage dealt" do
      battle = Rubowar::Battle.new([StationaryBot, StationaryBot], tick_limit: 1)
      battle.run

      # Same damage dealt, different HP
      battle.arena.runners[0].damage_dealt = 50
      battle.arena.runners[0].health = 80
      battle.arena.runners[1].damage_dealt = 50
      battle.arena.runners[1].health = 90
      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.runners[1]
    end
  end

  describe "phased action processing" do
    it "fires bullets from post-movement position" do
      battle = Rubowar::Battle.new([PositionRecordingBot, StationaryBot], tick_limit: 1)

      # Position bot at known location, facing east
      mover = battle.arena.runners.find { |r| r.instance.is_a?(PositionRecordingBot) }
      mover.x = 100.0
      mover.y = 300.0
      mover.turret_angle = 0 # Facing east

      battle.send(:call_on_spawn)
      battle.send(:run_tick)

      # Bot thrusted east at speed 10, so it moved ~10 pixels east
      # Bullet should spawn from the NEW position, not the old one
      bullet = battle.arena.bullets.first
      _(bullet).wont_be_nil

      # Bullet x should be greater than starting x (100) + radius
      # because bot moved east before firing
      _(bullet.x).must_be :>, 100 + mover.radius
    end

    it "processes all rubots movement before any rubot fires" do
      battle = Rubowar::Battle.new([MoveAndFireBot, MoveAndFireBot], tick_limit: 1)

      # Position both bots
      bot_a = battle.arena.runners[0]
      bot_b = battle.arena.runners[1]

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

      battle.send(:run_tick)

      # Both bots should have moved north before firing
      # Their bullets should spawn from y > 300 (moved north)
      bullets = battle.arena.bullets
      _(bullets.length).must_equal 2
      _(bullets.all? { |b| b.y > 300 }).must_equal true
    end

    it "processes sensing before movement" do
      # Create a battle where pulse happens before movement
      battle = Rubowar::Battle.new([PulseTestBot, StationaryBot], tick_limit: 2)

      pulser = battle.arena.runners.find { |r| r.instance.is_a?(PulseTestBot) }
      target = battle.arena.runners.find { |r| r.instance.is_a?(StationaryBot) }

      # Position them close together
      pulser.x = 200.0
      pulser.y = 300.0
      target.x = 250.0
      target.y = 300.0

      battle.send(:call_on_spawn)
      battle.send(:run_tick)
      battle.send(:run_tick)

      # Pulse from tick 1 should detect target at its pre-movement position
      results = pulser.instance.pulse_results_per_tick
      _(results[1]).wont_be_empty
    end

    it "deducts sensing energy before combat energy" do
      # If a bot queues fire() then pulse(), pulse should still execute first
      # and use energy first, potentially leaving less for fire
      battle = Rubowar::Battle.new([MoveAndFireBot, StationaryBot], tick_limit: 1)

      bot = battle.arena.runners.find { |r| r.instance.is_a?(MoveAndFireBot) }
      bot.x = 400.0
      bot.y = 300.0
      bot.energy = 15 # Only enough for fire(10) OR pulse, not both

      # Redefine tick to fire first, then pulse
      bot.instance.define_singleton_method(:tick) do
        fire(10)      # Queued first in code
        pulse(distance: 100)  # Queued second, but processed first!
        thrust(speed: 1, angle: 0)
      end

      battle.send(:call_on_spawn)
      battle.send(:run_tick)

      # Pulse costs ~4 energy (2 base + 100/75 ceil = 4)
      # Fire costs 10 energy
      # With 15 energy: pulse takes 4, leaving 11 for fire - should succeed
      # But if fire went first: fire takes 10, leaving 5 for pulse
      # The pulse result being set proves pulse executed
      _(bot.instance.pulse_result).wont_be_nil
    end
  end

  describe "detect action" do
    it "reports zero counts when not being sensed" do
      battle = Rubowar::Battle.new([DetectTestBot, StationaryBot], tick_limit: 2)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      target = battle.arena.runners.find { |r| r.instance.is_a?(StationaryBot) }

      # Position them far apart so no sensing happens
      detector.x = 100.0
      detector.y = 100.0
      target.x = 500.0
      target.y = 500.0

      battle.send(:call_on_spawn)
      battle.send(:run_tick)

      # After first tick, detect_result should show zero counts
      result = detector.instance.detect_result
      _(result).wont_be_nil
      _(result[:probed]).must_equal 0
      _(result[:scanned]).must_equal 0
      _(result[:pulsed]).must_equal 0
    end

    it "reports probe count when probed" do
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], tick_limit: 2)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.runners.find { |r| r.instance.is_a?(SensingBot) }

      # Position sensor to aim at detector
      sensor.x = 100.0
      sensor.y = 300.0
      sensor.turret_angle = 0 # Facing east
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_probe = true  # Set AFTER on_spawn resets it
      battle.send(:run_tick)

      # Detector should report being probed
      result = detector.instance.detect_result
      _(result[:probed]).must_equal 1
      _(result[:scanned]).must_equal 0
      _(result[:pulsed]).must_equal 0
    end

    it "reports scan count when scanned" do
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], tick_limit: 2)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.runners.find { |r| r.instance.is_a?(SensingBot) }

      # Position them close enough for scan
      sensor.x = 100.0
      sensor.y = 300.0
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_scan = true  # Set AFTER on_spawn resets it
      battle.send(:run_tick)

      # Detector should report being scanned
      result = detector.instance.detect_result
      _(result[:probed]).must_equal 0
      _(result[:scanned]).must_equal 1
      _(result[:pulsed]).must_equal 0
    end

    it "reports pulse count when pulsed" do
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], tick_limit: 2)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.runners.find { |r| r.instance.is_a?(SensingBot) }

      # Position them close enough for pulse
      sensor.x = 100.0
      sensor.y = 300.0
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_pulse = true  # Set AFTER on_spawn resets it
      battle.send(:run_tick)

      # Detector should report being pulsed
      result = detector.instance.detect_result
      _(result[:probed]).must_equal 0
      _(result[:scanned]).must_equal 0
      _(result[:pulsed]).must_equal 1
    end

    it "reports combined counts from multiple sensors" do
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot, SensingBot], tick_limit: 2)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      sensors = battle.arena.runners.select { |r| r.instance.is_a?(SensingBot) }

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
      battle.send(:run_tick)

      # Detector should report being pulsed twice
      result = detector.instance.detect_result
      _(result[:pulsed]).must_equal 2
    end

    it "resets counts each tick" do
      battle = Rubowar::Battle.new([DetectTestBot, SensingBot], tick_limit: 3)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      sensor = battle.arena.runners.find { |r| r.instance.is_a?(SensingBot) }

      # Position them close
      sensor.x = 100.0
      sensor.y = 300.0
      detector.x = 200.0
      detector.y = 300.0

      battle.send(:call_on_spawn)
      sensor.instance.do_pulse = true  # Set AFTER on_spawn resets it
      battle.send(:run_tick)

      # First tick: pulsed
      _(detector.instance.detect_result[:pulsed]).must_equal 1

      # Stop pulsing
      sensor.instance.do_pulse = false
      battle.send(:run_tick)

      # Second tick: not pulsed (counts reset)
      _(detector.instance.detect_result[:pulsed]).must_equal 0
    end

    it "costs 2 energy" do
      battle = Rubowar::Battle.new([DetectTestBot, StationaryBot], tick_limit: 1)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      detector.energy = 50

      battle.send(:call_on_spawn)
      battle.send(:run_tick)

      # Energy should have decreased by 2 (detect cost) plus regen
      # Starting: 50, detect: -2, regen: +10 = 58
      _(detector.energy).must_equal 58
    end

    it "returns false and fails when insufficient energy" do
      battle = Rubowar::Battle.new([DetectTestBot, StationaryBot], tick_limit: 1)

      detector = battle.arena.runners.find { |r| r.instance.is_a?(DetectTestBot) }
      detector.energy = 1 # Not enough for detect (costs 2)

      battle.send(:call_on_spawn)
      battle.send(:run_tick)

      # detect_result should be nil (action failed)
      _(detector.instance.detect_result).must_be_nil
    end
  end
end
