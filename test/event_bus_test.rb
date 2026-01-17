# frozen_string_literal: true

require "test_helper"
require "concurrent"

describe Rubowar::EventBus do
  describe "initialization" do
    it "starts at chronon zero" do
      event_bus = Rubowar::EventBus.new

      _(event_bus.current_chronon).must_equal 0
    end

    it "accepts custom chronon limit" do
      event_bus = Rubowar::EventBus.new(chronon_limit: 500)

      _(event_bus.chronon_limit).must_equal 500
    end

    it "rejects zero chronon limit" do
      _ { Rubowar::EventBus.new(chronon_limit: 0) }.must_raise Rubowar::InvalidChrononLimitError
    end

    it "rejects negative chronon limit" do
      _ { Rubowar::EventBus.new(chronon_limit: -1) }.must_raise Rubowar::InvalidChrononLimitError
    end

    it "rejects infinite chronon limit" do
      _ { Rubowar::EventBus.new(chronon_limit: Float::INFINITY) }.must_raise Rubowar::InvalidChrononLimitError
    end
  end

  describe "subscription" do
    it "registers callback for event type" do
      event_bus = Rubowar::EventBus.new
      called = false
      event_bus.on(:death) { called = true }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "test-123"))

      _(called).must_equal true
    end

    it "passes event data to callback" do
      event_bus = Rubowar::EventBus.new
      received_data = nil
      event_bus.on(:death) { |data| received_data = data }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "test-123"))

      _(received_data[:actor_id]).must_equal "test-123"
    end

    it "injects current chronon into event data" do
      event_bus = Rubowar::EventBus.new
      event_bus.increment_chronon
      event_bus.increment_chronon
      received_data = nil
      event_bus.on(:death) { |data| received_data = data }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "test-123"))

      _(received_data[:chronon]).must_equal 2
    end

    it "supports multiple callbacks for same event" do
      event_bus = Rubowar::EventBus.new
      count = 0
      event_bus.on(:death) { count += 1 }
      event_bus.on(:death) { count += 1 }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "test-123"))

      _(count).must_equal 2
    end

    it "isolates callbacks by event type" do
      event_bus = Rubowar::EventBus.new
      death_called = false
      fire_called = false
      event_bus.on(:death) { death_called = true }
      event_bus.on(:fire) { fire_called = true }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "test-123"))

      _(death_called).must_equal true
      _(fire_called).must_equal false
    end
  end

  describe "chronon tracking" do
    it "increments chronon" do
      event_bus = Rubowar::EventBus.new

      event_bus.increment_chronon

      _(event_bus.current_chronon).must_equal 1
    end

    it "resets chronon to zero" do
      event_bus = Rubowar::EventBus.new
      3.times { event_bus.increment_chronon }

      event_bus.reset_chronon

      _(event_bus.current_chronon).must_equal 0
    end

    it "detects chronon limit reached" do
      event_bus = Rubowar::EventBus.new(chronon_limit: 3)

      _(event_bus.chronon_limit_reached?).must_equal false
      event_bus.increment_chronon
      _(event_bus.chronon_limit_reached?).must_equal false
      event_bus.increment_chronon
      _(event_bus.chronon_limit_reached?).must_equal false
      event_bus.increment_chronon
      _(event_bus.chronon_limit_reached?).must_equal true
    end
  end

  describe "event types" do
    it "emits Death event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:death) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-123"))

      _(received[:actor_id]).must_equal "rbot-123"
    end

    it "emits Error event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:error) { |data| received = data }
      error = StandardError.new("test error")

      event_bus.emit(Rubowar::EventBus::Error.new(actor_id: "rbot-123", error: error))

      _(received[:actor_id]).must_equal "rbot-123"
      _(received[:error]).must_equal error
    end

    it "emits Fire event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:fire) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::Fire.new(
                       actor_id: "rbot-123",
                       bullet_id: "bult-456",
                       x: 100.0,
                       y: 200.0,
                       angle: 45.0,
                       damage: 15
                     ))

      _(received[:actor_id]).must_equal "rbot-123"
      _(received[:bullet_id]).must_equal "bult-456"
      _(received[:damage]).must_equal 15
    end

    it "emits Hit event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:hit) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::Hit.new(
                       attacker_id: "rbot-123",
                       target_id: "rbot-456",
                       bullet_id: "bult-789",
                       x: 150.0,
                       y: 250.0,
                       damage: 20
                     ))

      _(received[:attacker_id]).must_equal "rbot-123"
      _(received[:target_id]).must_equal "rbot-456"
      _(received[:damage]).must_equal 20
    end

    it "emits Collision event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:collision) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::Collision.new(
                       actor_a_id: "rbot-123",
                       actor_b_id: "rbot-456",
                       damage_to_a: 5,
                       damage_to_b: 7
                     ))

      _(received[:actor_a_id]).must_equal "rbot-123"
      _(received[:damage_to_a]).must_equal 5
    end

    it "emits WallHit event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:wall_hit) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::WallHit.new(
                       actor_id: "rbot-123",
                       damage: 3,
                       walls: [:left]
                     ))

      _(received[:walls]).must_equal [:left]
    end

    it "emits EnergonSpawn event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:energon_spawn) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::EnergonSpawn.new(
                       energon_id: "enrg-123",
                       x: 300.0,
                       y: 400.0
                     ))

      _(received[:energon_id]).must_equal "enrg-123"
    end

    it "emits EnergonCollect event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:energon_collect) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::EnergonCollect.new(
                       actor_id: "rbot-123",
                       energon_id: "enrg-456",
                       x: 300.0,
                       y: 400.0,
                       amount: 25
                     ))

      _(received[:amount]).must_equal 25
    end

    it "emits BattleEnd event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:battle_end) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::BattleEnd.new(winner: nil, outcome: :draw))

      _(received[:outcome]).must_equal :draw
    end

    it "emits ActionFailed event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:action_failed) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::ActionFailed.new(
                       actor_id: "rbot-123",
                       action: :fire,
                       reason: "insufficient energy"
                     ))

      _(received[:actor_id]).must_equal "rbot-123"
      _(received[:action]).must_equal :fire
      _(received[:reason]).must_equal "insufficient energy"
    end

    it "emits Shield event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:shield) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::Shield.new(actor_id: "rbot-123", energy: 10))

      _(received[:actor_id]).must_equal "rbot-123"
      _(received[:energy]).must_equal 10
    end

    it "emits Chronon event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:chronon) { |data| received = data }
      actors = [:actor1, :actor2]
      bullets = [:bullet1]
      energons = []

      event_bus.emit(Rubowar::EventBus::Chronon.new(
                       chronon: 42,
                       actors: actors,
                       bullets: bullets,
                       energons: energons
                     ))

      _(received[:chronon]).must_equal 0 # Auto-injected chronon overrides
      _(received[:actors]).must_equal actors
      _(received[:bullets]).must_equal bullets
      _(received[:energons]).must_equal energons
    end

    it "emits EnergonSpawnFailed event" do
      event_bus = Rubowar::EventBus.new
      received = nil
      event_bus.on(:energon_spawn_failed) { |data| received = data }

      event_bus.emit(Rubowar::EventBus::EnergonSpawnFailed.new)

      _(received).wont_be_nil
      _(received[:chronon]).must_equal 0
    end
  end

  describe "callback errors" do
    it "executes all callbacks even when one raises" do
      event_bus = Rubowar::EventBus.new
      first_called = false
      third_called = false
      event_bus.on(:death) { first_called = true }
      event_bus.on(:death) { raise "callback error" }
      event_bus.on(:death) { third_called = true }

      _ { event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-123")) }.must_raise Rubowar::CallbackError

      _(first_called).must_equal true
      _(third_called).must_equal true
    end

    it "raises CallbackError with event type and collected errors" do
      event_bus = Rubowar::EventBus.new
      event_bus.on(:death) { raise ArgumentError, "bad argument" }
      event_bus.on(:death) { raise RuntimeError, "runtime failure" }

      error = _ { event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-123")) }.must_raise Rubowar::CallbackError

      _(error.event_type).must_equal :death
      _(error.errors.length).must_equal 2
      _(error.errors[0]).must_be_kind_of ArgumentError
      _(error.errors[1]).must_be_kind_of RuntimeError
      _(error.message).must_include "2 callback(s) failed for :death"
    end

    it "does not raise when no callbacks fail" do
      event_bus = Rubowar::EventBus.new
      called = false
      event_bus.on(:death) { called = true }

      event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-123"))

      _(called).must_equal true
    end
  end

  describe "thread safety" do
    it "handles concurrent emit calls without losing events" do
      event_bus = Rubowar::EventBus.new
      received_events = Concurrent::Array.new
      event_bus.on(:death) { |data| received_events << data }

      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-#{i}-#{j}"))
          end
        end
      end
      threads.each(&:join)

      _(received_events.length).must_equal 100
    end

    it "handles concurrent emit calls to different event types" do
      event_bus = Rubowar::EventBus.new
      death_events = Concurrent::Array.new
      fire_events = Concurrent::Array.new
      event_bus.on(:death) { |data| death_events << data }
      event_bus.on(:fire) { |data| fire_events << data }

      threads = []
      threads << Thread.new do
        50.times { |i| event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-#{i}")) }
      end
      threads << Thread.new do
        50.times do |i|
          event_bus.emit(Rubowar::EventBus::Fire.new(
                           actor_id: "rbot-#{i}",
                           bullet_id: "bult-#{i}",
                           x: 100.0,
                           y: 200.0,
                           angle: 45.0,
                           damage: 15
                         ))
        end
      end
      threads.each(&:join)

      _(death_events.length).must_equal 50
      _(fire_events.length).must_equal 50
    end

    it "handles concurrent chronon increments" do
      event_bus = Rubowar::EventBus.new(chronon_limit: 10_000)

      threads = 10.times.map do
        Thread.new do
          100.times { event_bus.increment_chronon }
        end
      end
      threads.each(&:join)

      _(event_bus.current_chronon).must_equal 1000
    end

    it "handles emit during callback execution" do
      event_bus = Rubowar::EventBus.new
      received_events = Concurrent::Array.new

      event_bus.on(:death) do |data|
        received_events << data
        # Simulate slow callback
        sleep(0.001)
      end

      threads = 5.times.map do |i|
        Thread.new do
          5.times do |j|
            event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-#{i}-#{j}"))
          end
        end
      end
      threads.each(&:join)

      _(received_events.length).must_equal 25
    end

    it "provides consistent chronon value during concurrent emits" do
      event_bus = Rubowar::EventBus.new
      event_bus.increment_chronon
      event_bus.increment_chronon
      event_bus.increment_chronon
      chronons_received = Concurrent::Array.new

      event_bus.on(:death) { |data| chronons_received << data[:chronon] }

      threads = 10.times.map do
        Thread.new do
          10.times { event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "test")) }
        end
      end
      threads.each(&:join)

      # All events should have chronon 3 (the value at emit time)
      _(chronons_received.all? { |c| c == 3 }).must_equal true
    end

    it "handles subscription completing before emit starts" do
      event_bus = Rubowar::EventBus.new
      results = Concurrent::Array.new

      # Use two latches to ensure deterministic ordering:
      # 1. subscription_ready: signals subscriber has registered
      # 2. emit_start: signals emitter can begin
      subscription_ready = Concurrent::CountDownLatch.new(1)
      emit_start = Concurrent::CountDownLatch.new(1)

      subscriber_thread = Thread.new do
        event_bus.on(:death) { |data| results << data }
        subscription_ready.count_down
        emit_start.wait # Wait for emitter to be ready
      end

      emitter_thread = Thread.new do
        subscription_ready.wait # Wait for subscription to complete
        emit_start.count_down
        10.times { |i| event_bus.emit(Rubowar::EventBus::Death.new(actor_id: "rbot-#{i}")) }
      end

      subscriber_thread.join
      emitter_thread.join

      # All events should be received since subscription completed before emit
      _(results.length).must_equal 10
    end
  end

  describe "registered_events" do
    it "returns empty array when no subscriptions" do
      event_bus = Rubowar::EventBus.new

      _(event_bus.registered_events).must_equal []
    end

    it "returns subscribed event types" do
      event_bus = Rubowar::EventBus.new
      event_bus.on(:death) { }
      event_bus.on(:fire) { }

      _(event_bus.registered_events).must_include :death
      _(event_bus.registered_events).must_include :fire
    end
  end
end
