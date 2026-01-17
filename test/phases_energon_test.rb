# frozen_string_literal: true

require "test_helper"

describe Rubowar::Phases::Energon do
  def build_arena(width: 640, height: 640)
    Rubowar::Arena.new(width:, height:, event_bus: Rubowar::EventBus.new)
  end

  def build_actor(x: 100.0, y: 100.0, energy: 50)
    klass = Class.new do
      include Rubowar::Rubot

      attr_accessor :collected_energon

      def act; end

      def on_energon(amount)
        @collected_energon = amount
      end
    end
    actor = Rubowar::LocalActor.new(klass)
    actor.set_position(x:, y:)
    actor.instance_variable_set(:@energy, energy)
    actor
  end

  describe ".execute" do
    it "returns empty collections when no energon exists" do
      arena = build_arena
      actor = build_actor
      arena.actors = [actor]

      result = Rubowar::Phases::Energon.execute(arena:, chronon: 1)

      _(result[:collections]).must_equal []
    end

    it "returns collections when rubot collects energon" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0, energy: 50)
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100.0, y: 100.0, spawn_chronon: 0)
      arena.energons << energon

      result = Rubowar::Phases::Energon.execute(arena:, chronon: 10)

      _(result[:collections].length).must_equal 1
      _(result[:collections].first[:actor]).must_equal actor
      _(result[:collections].first[:energon]).must_equal energon
    end

    it "triggers on_energon callback when collected" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0, energy: 50)
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100.0, y: 100.0, spawn_chronon: 0)
      arena.energons << energon

      Rubowar::Phases::Energon.execute(arena:, chronon: 10)

      _(actor.instance.collected_energon).must_equal energon.value_int(10)
    end

    it "spawns energon at spawn interval" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0)
      arena.actors = [actor]
      spawn_interval = Rubowar::Config::Arena::ENERGON_SPAWN_INTERVAL

      result = Rubowar::Phases::Energon.execute(arena:, chronon: spawn_interval)

      _(result[:spawned]).must_be_kind_of Rubowar::Energon
      _(result[:spawn_failed]).must_equal false
    end

    it "spawns energon at multiples of spawn interval" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0)
      arena.actors = [actor]
      spawn_interval = Rubowar::Config::Arena::ENERGON_SPAWN_INTERVAL

      result = Rubowar::Phases::Energon.execute(arena:, chronon: spawn_interval * 3)

      _(result[:spawned]).must_be_kind_of Rubowar::Energon
    end

    it "does not spawn energon between intervals" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0)
      arena.actors = [actor]
      spawn_interval = Rubowar::Config::Arena::ENERGON_SPAWN_INTERVAL

      result = Rubowar::Phases::Energon.execute(arena:, chronon: spawn_interval + 1)

      _(result[:spawned]).must_be_nil
      _(result[:spawn_failed]).must_equal false
    end

    it "sets spawn_failed when spawning fails" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0)
      arena.actors = [actor]
      spawn_interval = Rubowar::Config::Arena::ENERGON_SPAWN_INTERVAL

      # Stub spawn_energon to return nil (simulating spawn failure)
      arena.stub(:spawn_energon, nil) do
        result = Rubowar::Phases::Energon.execute(arena:, chronon: spawn_interval)

        _(result[:spawned]).must_be_nil
        _(result[:spawn_failed]).must_equal true
      end
    end

    it "adds spawned energon to arena" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0)
      arena.actors = [actor]
      spawn_interval = Rubowar::Config::Arena::ENERGON_SPAWN_INTERVAL
      initial_count = arena.energons.size

      Rubowar::Phases::Energon.execute(arena:, chronon: spawn_interval)

      _(arena.energons.size).must_equal initial_count + 1
    end

    it "removes collected energon from arena" do
      arena = build_arena
      actor = build_actor(x: 100.0, y: 100.0)
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100.0, y: 100.0, spawn_chronon: 0)
      arena.energons << energon

      Rubowar::Phases::Energon.execute(arena:, chronon: 10)

      _(arena.energons).wont_include energon
    end
  end
end
