# frozen_string_literal: true

require "test_helper"

describe Rubowar::Phases::Sense do
  def build_arena(width: 640, height: 640)
    Rubowar::Arena.new(width:, height:, event_bus: Rubowar::EventBus.new)
  end

  def build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 100)
    klass = Class.new do
      include Rubowar::Rubot

      def act; end
    end
    actor = Rubowar::LocalActor.new(klass)
    actor.set_position(x:, y:)
    actor.turret_angle = turret_angle
    actor.instance_variable_set(:@energy, energy)
    actor.reset_actions
    actor
  end

  describe ".execute" do
    it "resets detection counts for all actors" do
      arena = build_arena
      actor = build_actor
      arena.actors = [actor]
      actor.instance_variable_set(:@detection_counts, { probed: 5, scanned: 3, pulsed: 2 })

      Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      _(actor.detection_counts).must_equal({ probed: 0, scanned: 0, pulsed: 0 })
    end

    it "processes probe actions before detect" do
      arena = build_arena
      prober = build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 50)
      target = build_actor(x: 200.0, y: 100.0, turret_angle: 0.0, energy: 50)
      arena.actors = [prober, target]

      # Queue probe and detect actions
      prober.instance.actions[:sense] << { type: :probe, attributes: [:position] }
      prober.instance.actions[:sense] << { type: :detect }

      # Execute sense phase
      Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      # Prober should detect that they probed someone (themselves counts in detect)
      _(prober.instance.detect_intel).must_be_kind_of Rubowar::DetectIntel
      _(prober.instance.detect_intel.probed).must_equal 0 # Only counts when you are the target
      # Target should have been probed once
      _(target.detection_counts[:probed]).must_equal 1
    end

    it "processes scan actions and increments detection counts" do
      arena = build_arena
      scanner = build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 50)
      target = build_actor(x: 150.0, y: 100.0, turret_angle: 0.0, energy: 50)
      arena.actors = [scanner, target]

      # Queue scan action
      scanner.instance.actions[:sense] << { type: :scan, angle: 120, distance: 100, velocity: false, owner: false }

      Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      # Target should have been scanned
      _(target.detection_counts[:scanned]).must_equal 1
    end

    it "processes pulse actions and increments detection counts" do
      arena = build_arena
      pulser = build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 50)
      target = build_actor(x: 150.0, y: 100.0, turret_angle: 0.0, energy: 50)
      arena.actors = [pulser, target]

      # Queue pulse action
      pulser.instance.actions[:sense] << { type: :pulse, distance: 100, owner: false }

      Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      # Target should have been pulsed
      _(target.detection_counts[:pulsed]).must_equal 1
    end

    it "processes detect last so it reports current chronon counts" do
      arena = build_arena
      actor_a = build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 50)
      actor_b = build_actor(x: 200.0, y: 100.0, turret_angle: 0.0, energy: 50)
      arena.actors = [actor_a, actor_b]

      # A probes B, B detects
      actor_a.instance.actions[:sense] << { type: :probe, attributes: [:position] }
      actor_b.instance.actions[:sense] << { type: :detect }

      Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      # B should detect being probed
      _(actor_b.instance.detect_intel).must_be_kind_of Rubowar::DetectIntel
      _(actor_b.instance.detect_intel.probed).must_equal 1
    end

    it "returns failed actions when energy is insufficient" do
      arena = build_arena
      actor = build_actor(energy: 0)
      arena.actors = [actor]

      # Queue action that requires energy
      actor.instance.actions[:sense] << { type: :probe, attributes: [:position] }

      failures = Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      _(failures).must_be_kind_of Array
      _(failures.size).must_equal 1
      _(failures.first[:actor]).must_equal actor
    end

    it "applies error damage for invalid actions" do
      arena = build_arena
      actor = build_actor(energy: 50)
      arena.actors = [actor]
      initial_health = actor.health

      # Queue invalid action (negative distance)
      actor.instance.actions[:sense] << { type: :scan, angle: 120, distance: -100, velocity: false, owner: false }

      failures = Rubowar::Phases::Sense.execute(arena:, actors: arena.actors)

      _(actor.health).must_be :<, initial_health
      _(failures.first[:error]).must_be_kind_of Rubowar::InvalidActionError
    end
  end
end
