# frozen_string_literal: true

require "concurrent"

# [file]
# purpose = "Minimal actor implementation for testing and external control"
# responsibility = "Implements actor interface without a real rubot instance"
# pattern = "Null Object / Adapter"
#
# [class.BasicActor]
# purpose = "Lightweight actor for testing and external sources"
# note = "Unlike LocalActor which wraps a Rubot, BasicActor has no rubot instance"
# usage = "Actions are set directly via set_actions(), act() is a no-op"
# use_cases = [
#   "Testing Battle's duck type interface",
#   "Simulating network/remote actors",
#   "Reference implementation for custom actors"
# ]
# thread_safety = "Uses Concurrent::Future instead of Timeout.timeout to avoid unsafe Thread#raise"

module Rubowar
  class BasicActor
    include RubotActor
    include RubotPhysics

    def initialize(size: :medium, health: nil, energy: nil, name: "BasicActor")
      validate_size!(size)
      initialize_actor(size:, name:)
      @health = health || max_health
      @energy = energy || max_energy
      @_actions = { sense: [], move: [], combat: [] }
      @_sensing_results = {}
    end

    # === Identity (for Battle compatibility) ===

    def rubot_class
      @rubot_class ||= Class.new do
        def self.name
          "BasicActor"
        end
      end
    end

    def instance
      self
    end

    # === Action Management ===

    def rubot_actions
      @_actions
    end

    def reset_actions
      @_actions = { sense: [], move: [], combat: [] }
    end

    def act
      # No-op: actions are set externally via set_actions
    end

    # Test helper: pre-set actions that will be processed by Battle phases
    def set_actions(sense: [], move: [], combat: [])
      @_actions = { sense:, move:, combat: }
    end

    # === State Setup (called by Battle each chronon) ===

    def rubot_state=(state)
      @_rubot_state = state
    end

    def arena_state=(state)
      @_arena_state = state
    end

    attr_writer :_pending_energy_spend

    # === Sensing Results ===

    def set_sensing_results(probe: nil, scan: nil, pulse: nil, detect: nil)
      @_sensing_results[:probe] = ProbeEcho.from_hash(probe) unless probe.nil?
      @_sensing_results[:scan] = ScanEcho.new(scan) unless scan.nil?
      @_sensing_results[:pulse] = PulseEcho.new(pulse) unless pulse.nil?
      @_sensing_results[:detect] = DetectIntel.from_hash(detect) unless detect.nil?
    end

    # Sensing result accessors (for compatibility with rubot instance pattern)
    def probe_echo
      @_sensing_results[:probe]
    end

    def scan_echo
      @_sensing_results[:scan]
    end

    def pulse_echo
      @_sensing_results[:pulse]
    end

    def detect_intel
      @_sensing_results[:detect]
    end

    # === Callbacks ===

    # Uses Concurrent::Future instead of Timeout.timeout because Ruby's Timeout uses
    # Thread#raise which can interrupt code at unsafe points.
    def call_safely
      return nil unless alive?

      future = Concurrent::Future.execute { yield self }
      result = future.value(Config::Battle::CALLBACK_TIMEOUT)

      if future.fulfilled?
        result
      elsif future.rejected?
        apply_collision_damage(Config::Battle::ERROR_DAMAGE)
        warn "[#{name}] Error in callback: #{future.reason.class} - #{future.reason.message}"
        nil
      else
        # Timeout - future is still pending
        apply_collision_damage(Config::Battle::ERROR_DAMAGE)
        warn "[#{name}] Callback timed out after #{Config::Battle::CALLBACK_TIMEOUT}s"
        nil
      end
    end

    def call_on_death
      # No-op for basic actor: no rubot instance to call
    end

    # Callback stubs (for call_safely compatibility)
    def on_spawn; end
    def on_hit(damage:, direction:); end
    def on_wall; end
    def on_collision(other_state); end
    def on_energon(amount); end
    def on_death; end
  end
end
