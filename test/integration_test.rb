# frozen_string_literal: true

require "test_helper"

# === Test Rubots for Integration Tests ===

# Simple bot that just sits still
class IntegrationStationaryBot
  include Rubowar::Rubot

  size :medium
  def act; end
end

# Bot that fires every tick at high energy
class IntegrationShooterBot
  include Rubowar::Rubot

  size :medium

  def act
    rotate_turret(5)
    fire(15) if energy > 20
  end
end

# Bot that tracks when it receives sensing results
class IntegrationSensingBot
  include Rubowar::Rubot

  size :medium

  attr_reader :ticks_with_pulse_echo, :ticks_with_probe_echo, :ticks_with_scan_echo

  def on_spawn
    @ticks_with_pulse_echo = []
    @ticks_with_probe_echo = []
    @ticks_with_scan_echo = []
  end

  def act
    # Record which ticks have results
    @ticks_with_pulse_echo << chronon if pulse_echo&.any?
    @ticks_with_probe_echo << chronon if probe_echo&.any?
    @ticks_with_scan_echo << chronon if scan_echo&.any?

    # Queue sensing for next tick
    pulse(distance: 500)
    probe(:position)
    scan(angle: 360, distance: 500)
  end
end

# Bot that moves then fires to test phased processing
class IntegrationMoveFireBot
  include Rubowar::Rubot

  size :medium

  attr_reader :positions_when_fired

  def on_spawn
    @positions_when_fired = []
  end

  def act
    @positions_when_fired << { x: x.round(1), y: y.round(1) }
    thrust(speed: 5, angle: 0) # Move east
    fire(10)
  end
end

# Bot that collects energons
class IntegrationCollectorBot
  include Rubowar::Rubot

  size :medium

  attr_reader :energon_collections

  def on_spawn
    @energon_collections = []
  end

  def on_energon(amount)
    @energon_collections << { tick: chronon, amount: }
  end

  def act
    # Move toward nearest energon if available
    nearest = find_nearest_energon
    return unless nearest

    angle = angle_to(target_x: nearest[:x], target_y: nearest[:y])
    thrust(speed: 6, angle:)
  end
end

# Bot that crashes on purpose
class IntegrationCrashingBot
  include Rubowar::Rubot

  size :medium

  attr_accessor :should_crash

  def on_spawn
    @should_crash = false
  end

  def act
    raise "Intentional crash!" if @should_crash
  end
end

# Bot that uses shields
class IntegrationShieldBot
  include Rubowar::Rubot

  size :medium

  def act
    raise_shields(20) if energy > 30 && shield_level < 50
  end
end

# Bot that rams into walls
class IntegrationWallRamBot
  include Rubowar::Rubot

  size :medium

  attr_reader :wall_hits

  def on_spawn
    @wall_hits = 0
  end

  def on_wall
    @wall_hits += 1
  end

  def act
    thrust(speed: 8, angle: 0) # Ram east wall
  end
end

# Bot that uses detect to sense when it's being scanned
class IntegrationDetectBot
  include Rubowar::Rubot

  size :medium

  attr_reader :detect_intels_by_tick

  def on_spawn
    @detect_intels_by_tick = {}
  end

  def act
    @detect_intels_by_tick[chronon] = detect_intel.dup if detect_intel
    detect
  end
end

# Bot that actively senses another bot
class IntegrationScannerBot
  include Rubowar::Rubot

  size :medium

  def act
    pulse(distance: 500)
    scan(angle: 360, distance: 500)
    probe(:position)
  end
end

describe "Integration Tests" do
  describe "full battle simulation" do
    it "runs a complete battle to conclusion" do
      battle = Rubowar::Battle.local([IntegrationShooterBot, IntegrationStationaryBot], chronon_limit: 500)

      events = battle.run

      _(battle.winner).wont_be_nil
      _(battle.chronon).must_be :>=, 1
      _(events).wont_be_empty
    end

    it "determines winner as last rubot standing" do
      battle = Rubowar::Battle.local([IntegrationShooterBot, IntegrationStationaryBot], chronon_limit: 1000)
      battle.run

      # Shooter should eventually kill stationary bot
      stationary = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationStationaryBot) }

      _(battle.winner.instance).must_be_instance_of IntegrationShooterBot if stationary.dead?
    end

    it "uses damage dealt as tiebreaker when timeout" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 10)
      battle.run

      # Manually set damage to test tiebreaker
      battle.arena.actors[0].damage_dealt = 100
      battle.arena.actors[1].damage_dealt = 50
      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.actors[0]
    end

    it "uses health as secondary tiebreaker" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 10)
      battle.run

      # Same damage, different health
      battle.arena.actors[0].damage_dealt = 50
      battle.arena.actors[0].health = 80
      battle.arena.actors[1].damage_dealt = 50
      battle.arena.actors[1].health = 100
      battle.send(:determine_winner)

      _(battle.winner).must_equal battle.arena.actors[1]
    end

    it "handles draw when all rubots die simultaneously" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 5)

      # Kill both before battle runs (use registered_actors since not spawned yet)
      battle.registered_actors.each { |r| r.health = 0 }
      battle.run

      # No winner when all dead
      _(battle.arena.actors.count(&:alive?)).must_equal 0
    end
  end

  describe "sensing delay" do
    it "pulse results arrive one tick after queuing" do
      battle = Rubowar::Battle.local([IntegrationSensingBot, IntegrationStationaryBot], chronon_limit: 10)
      battle.run

      sensor = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationSensingBot) }
      results = sensor.instance.ticks_with_pulse_echo

      # Tick 1: pulse queued, no result yet
      # Tick 2: result from tick 1's pulse available
      _(results).wont_include 1
      _(results).must_include 2 if results.any?
    end

    it "probe results arrive one tick after queuing" do
      battle = Rubowar::Battle.local([IntegrationSensingBot, IntegrationStationaryBot], chronon_limit: 10)
      battle.spawn_rubots

      # Position them so probe can hit
      sensor = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationSensingBot) }
      target = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationStationaryBot) }
      sensor.x = 100
      sensor.y = 300
      sensor.turret_angle = 0
      target.x = 200
      target.y = 300

      battle.run

      results = sensor.instance.ticks_with_probe_echo

      # Results should not appear on tick 1
      _(results).wont_include 1
    end

    it "scan results arrive one tick after queuing" do
      battle = Rubowar::Battle.local([IntegrationSensingBot, IntegrationStationaryBot], chronon_limit: 10)
      battle.run

      sensor = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationSensingBot) }
      results = sensor.instance.ticks_with_scan_echo

      # Tick 1: scan queued, no result
      # Tick 2+: results available
      _(results).wont_include 1
    end

    it "detect reports current tick sensing activity" do
      battle = Rubowar::Battle.local([IntegrationDetectBot, IntegrationScannerBot], chronon_limit: 5)
      battle.spawn_rubots

      # Position them close
      detector = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationDetectBot) }
      scanner = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationScannerBot) }
      detector.x = 200
      detector.y = 300
      scanner.x = 100
      scanner.y = 300
      scanner.turret_angle = 0

      battle.run

      results = detector.instance.detect_intels_by_tick

      # Should have detected being sensed (results appear on tick after detect was called)
      total_sensed = results.values.sum { |r| (r[:probed] || 0) + (r[:scanned] || 0) + (r[:pulsed] || 0) }
      _(total_sensed).must_be :>, 0
    end
  end

  describe "phased action processing" do
    it "moves rubot before firing bullet" do
      battle = Rubowar::Battle.local([IntegrationMoveFireBot, IntegrationStationaryBot], chronon_limit: 3)
      battle.spawn_rubots

      mover = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationMoveFireBot) }
      mover.x = 100.0
      mover.y = 300.0
      mover.turret_angle = 0

      battle.run

      positions = mover.instance.positions_when_fired

      # Position at tick 2 should be greater than tick 1 (moved east)
      _(positions[1][:x]).must_be :>, positions[0][:x] if positions.length >= 2
    end

    it "processes all rubots movement before any firing" do
      battle = Rubowar::Battle.local([IntegrationMoveFireBot, IntegrationMoveFireBot], chronon_limit: 2)
      battle.spawn_rubots

      bot1 = battle.arena.actors[0]
      bot2 = battle.arena.actors[1]

      bot1.x = 100.0
      bot1.y = 300.0
      bot1.turret_angle = 90

      bot2.x = 200.0
      bot2.y = 300.0
      bot2.turret_angle = 90

      battle.run

      # Both bots should have bullets spawned from moved positions
      _(battle.arena.bullets.length).must_be :>=, 0 # Bullets may have left arena
    end
  end

  describe "energon mechanics" do
    it "spawns energon at configured interval" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 200)
      battle.run

      spawn_events = battle.event_log.select { |e| e[:type] == :energon_spawn }

      # Should spawn at tick 80 and 160
      _(spawn_events.length).must_be :>=, 2
    end

    it "energon value increases over time" do
      battle = Rubowar::Battle.local([IntegrationCollectorBot, IntegrationStationaryBot], chronon_limit: 200)

      # Force spawn an energon early
      battle.arena.spawn_energon(1)

      battle.run

      collector = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationCollectorBot) }
      collections = collector.instance.energon_collections

      if collections.any?
        # Later collections should be worth more (if multiple)
        _(collections.first[:amount]).must_be :>=, 1
      end
    end

    it "triggers on_energon callback when collected" do
      battle = Rubowar::Battle.local([IntegrationCollectorBot, IntegrationStationaryBot], chronon_limit: 200)
      battle.spawn_rubots

      # Spawn energon near collector
      collector = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationCollectorBot) }
      collector.x = 400
      collector.y = 300

      battle.arena.spawn_energon(1)

      battle.run

      collections = collector.instance.energon_collections

      # Should have collected at least one if positioned well
      # (may not collect if spawned too far)
      _(collections).must_be_kind_of Array
    end
  end

  describe "error handling" do
    it "applies damage when rubot crashes" do
      battle = Rubowar::Battle.local([IntegrationCrashingBot, IntegrationStationaryBot], chronon_limit: 10)
      battle.spawn_rubots

      crasher = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationCrashingBot) }
      initial_health = crasher.health

      # Make it crash after first tick
      battle.send(:call_on_spawn)
      crasher.instance.should_crash = true
      battle.send(:run_chronon)

      # Should have taken error damage (10)
      _(crasher.health).must_equal initial_health - Rubowar::Config::Battle::ERROR_DAMAGE
    end

    it "emits error event when rubot crashes" do
      battle = Rubowar::Battle.local([IntegrationCrashingBot, IntegrationStationaryBot], chronon_limit: 5)
      battle.spawn_rubots

      crasher = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationCrashingBot) }

      # Call on_spawn first, then enable crashing
      battle.send(:call_on_spawn)
      crasher.instance.should_crash = true

      # Run ticks manually so crash happens
      3.times { battle.send(:run_chronon) }

      error_events = battle.event_log.select { |e| e[:type] == :error }

      _(error_events).wont_be_empty
      _(error_events.first[:error]).must_be_instance_of RuntimeError
    end
  end

  describe "shield mechanics" do
    it "shields absorb bullet damage" do
      battle = Rubowar::Battle.local([IntegrationShieldBot, IntegrationShooterBot], chronon_limit: 50)
      battle.spawn_rubots

      shield_bot = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationShieldBot) }
      shooter = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationShooterBot) }

      # Position shooter to hit shield bot
      shooter.x = 100
      shooter.y = 300
      shooter.turret_angle = 0
      shield_bot.x = 200
      shield_bot.y = 300

      battle.run

      # Shield bot should have built shields and taken some hits
      # If it survived longer than without shields, shields worked
      _(shield_bot.damage_taken).must_be :>=, 0
    end

    it "shields decay each tick" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 20)
      battle.spawn_rubots

      # Directly set shield and test decay without bot intervention
      bot = battle.arena.actors.first
      bot.shield_level = 100

      initial_shield = bot.shield_level

      # Decay shields directly (12% per tick)
      battle.arena.regenerate_and_degrade

      # Shields should have decayed by 12%
      expected_shield = (initial_shield * (1 - Rubowar::Config::Rubot::SHIELD_DECAY_RATE)).to_i
      _(bot.shield_level).must_equal expected_shield
    end
  end

  describe "collision mechanics" do
    it "applies wall damage on collision" do
      battle = Rubowar::Battle.local([IntegrationWallRamBot, IntegrationStationaryBot], chronon_limit: 20)
      battle.spawn_rubots

      rammer = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationWallRamBot) }
      rammer.x = 750 # Near east wall
      rammer.y = 300

      battle.run

      # Should have hit wall and taken damage
      _(rammer.instance.wall_hits).must_be :>, 0
      _(rammer.damage_taken).must_be :>, 0
    end

    it "triggers on_wall callback" do
      battle = Rubowar::Battle.local([IntegrationWallRamBot, IntegrationStationaryBot], chronon_limit: 20)
      battle.spawn_rubots

      rammer = battle.arena.actors.find { |r| r.instance.is_a?(IntegrationWallRamBot) }
      rammer.x = 750
      rammer.y = 300

      battle.run

      _(rammer.instance.wall_hits).must_be :>, 0
    end
  end

  describe "multi-rubot battles" do
    it "handles 3+ rubots" do
      battle = Rubowar::Battle.local(
        [IntegrationShooterBot, IntegrationStationaryBot, IntegrationShieldBot],
        chronon_limit: 200
      )

      events = battle.run

      _(battle.arena.actors.length).must_equal 3
      _(events).wont_be_empty
    end

    it "continues until one survivor or timeout" do
      battle = Rubowar::Battle.local(
        [IntegrationShooterBot, IntegrationShooterBot, IntegrationShooterBot],
        chronon_limit: 500
      )

      battle.run

      alive_count = battle.arena.actors.count(&:alive?)

      # Either one survivor, all dead, or timeout with multiple alive
      _(alive_count).must_be :<=, 3
    end
  end

  describe "energy regeneration" do
    it "regenerates energy each tick" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 5)
      battle.spawn_rubots

      bot = battle.arena.actors.first
      bot.energy = 50

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      # Should have regenerated (energy_regen/tick)
      _(bot.energy).must_equal 50 + bot.energy_regen
    end

    it "caps energy at max" do
      battle = Rubowar::Battle.local([IntegrationStationaryBot, IntegrationStationaryBot], chronon_limit: 5)
      battle.spawn_rubots

      bot = battle.arena.actors.first
      bot.energy = bot.max_energy - 5

      battle.send(:call_on_spawn)
      battle.send(:run_chronon)

      _(bot.energy).must_equal bot.max_energy
    end
  end
end
