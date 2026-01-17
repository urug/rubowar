# frozen_string_literal: true

require "concurrent"

# [file]
# purpose = "Event bus with chronon tracking and typed events"
# responsibility = "Pub/sub for game events, scoped per battle instance"
# pattern = "Event Bus with Data.define event types"
#
# [class.EventBus]
# purpose = "Per-battle event bus for game events and chronon tracking"
# publish = "event_bus.emit(EventBus::BattleEnd.new(...))"
# subscribe = "event_bus.on(:battle_end) { |data| ... }"
# chronon = "event_bus.current_chronon, increment_chronon, reset_chronon"
#
# [event_categories]
# battle = "Chronon, BattleEnd, Death, Error, ActionFailed"
# combat = "Fire, Hit, Shield"
# physics = "Collision, WallHit"
# energon = "EnergonSpawn, EnergonCollect, EnergonSpawnFailed"
#
# [auto_injected]
# chronon = "All emitted events automatically include :chronon key"
#
# [thread_safety]
# design = "Thread-safe for concurrent emit() calls from multiple threads"
# implementation = "Uses Concurrent::Map for listeners, Concurrent::AtomicFixnum for chronon"
# note = "Listeners should be registered before battle.run() for deterministic behavior"

module Rubowar
  class EventBus
    # === Event Definitions ===
    #
    # Each event is a Data.define with explicit event_type method.
    # Usage: event_bus.emit(EventBus::BattleEnd.new(winner: actor, outcome: :victory))

    # Battle lifecycle events
    Chronon = Data.define(:chronon, :actors, :bullets, :energons) do
      def event_type = :chronon
    end

    BattleEnd = Data.define(:winner, :outcome) do
      def event_type = :battle_end
    end

    Death = Data.define(:actor_id) do
      def event_type = :death
    end

    Error = Data.define(:actor_id, :error) do
      def event_type = :error
    end

    ActionFailed = Data.define(:actor_id, :action, :reason) do
      def event_type = :action_failed
    end

    # Combat events
    Fire = Data.define(:actor_id, :bullet_id, :x, :y, :angle, :damage) do
      def event_type = :fire
    end

    Hit = Data.define(:attacker_id, :target_id, :bullet_id, :x, :y, :damage) do
      def event_type = :hit
    end

    Shield = Data.define(:actor_id, :energy) do
      def event_type = :shield
    end

    # Physics events
    Collision = Data.define(:actor_a_id, :actor_b_id, :damage_to_a, :damage_to_b) do
      def event_type = :collision
    end

    WallHit = Data.define(:actor_id, :damage, :walls) do
      def event_type = :wall_hit
    end

    # Energon events
    EnergonSpawn = Data.define(:energon_id, :x, :y) do
      def event_type = :energon_spawn
    end

    EnergonCollect = Data.define(:actor_id, :energon_id, :x, :y, :amount) do
      def event_type = :energon_collect
    end

    EnergonSpawnFailed = Data.define do
      def event_type = :energon_spawn_failed
    end

    # === Instance Methods ===

    def initialize(chronon_limit: Config::Battle::DEFAULT_CHRONON_LIMIT)
      validate_chronon_limit!(chronon_limit)

      # Thread-safe map for listeners. Each event type maps to an array of callbacks.
      # Using Concurrent::Map ensures safe concurrent access across Ruby implementations.
      @listeners = Concurrent::Map.new
      @listeners_mutex = Mutex.new

      # Thread-safe atomic counter for chronon tracking.
      # Ensures increment_chronon is atomic even under concurrent access.
      @chronon = Concurrent::AtomicFixnum.new(0)
      @chronon_limit = chronon_limit
    end

    attr_reader :chronon_limit

    # === Subscription ===

    # Register a callback for an event type.
    # Thread-safe: can be called concurrently, though registering during emit()
    # may result in the new callback missing in-flight events.
    #
    # IMPORTANT: Callbacks should be non-blocking. A callback that blocks
    # indefinitely will prevent subsequent callbacks from executing and
    # may cause the battle to hang.
    def on(event_type, &block)
      @listeners_mutex.synchronize do
        callbacks = @listeners.fetch(event_type, [])
        @listeners[event_type] = callbacks + [block]
      end
    end

    # === Publishing ===

    # Emits a typed event to all subscribers. Automatically injects current chronon.
    # Thread-safe: can be called concurrently from multiple threads.
    # Callback errors are captured and re-raised as CallbackError, but all callbacks execute.
    # @param event [Data] A typed event instance (e.g., EventBus::BattleEnd.new(...))
    def emit(event)
      data_with_chronon = event.to_h.merge(chronon: @chronon.value)
      # Fetch callbacks snapshot - safe even if new callbacks are added concurrently
      callbacks = @listeners.fetch(event.event_type, [])
      errors = []
      callbacks.each do |callback|
        callback.call(data_with_chronon)
      rescue => e
        errors << e
      end
      raise CallbackError.new(event.event_type, errors) if errors.any?
    end

    # === Chronon tracking ===

    def current_chronon
      @chronon.value
    end

    def increment_chronon
      @chronon.increment
    end

    def reset_chronon
      @chronon.value = 0
    end

    def chronon_limit_reached?
      @chronon.value >= @chronon_limit
    end

    # === Utilities ===

    # For debugging: list all registered event types
    def registered_events
      @listeners.keys
    end

    private

    def validate_chronon_limit!(chronon_limit)
      raise InvalidChrononLimitError, "chronon_limit must be positive" unless chronon_limit.positive?
      raise InvalidChrononLimitError, "chronon_limit must be finite" if chronon_limit.respond_to?(:infinite?) && chronon_limit.infinite?
    end
  end
end
