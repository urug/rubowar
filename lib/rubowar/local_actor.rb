# frozen_string_literal: true

require "forwardable"
require "timeout"

# [file]
# purpose = "Actor that wraps a local Rubot instance"
# responsibility = "Execute rubot code in-process with full state tracking"
# pattern = "Adapter/Wrapper"
#
# [class.LocalActor]
# purpose = "Wraps a Rubot instance with mutable game state for local execution"
# note = "Players never interact with this directly - they get immutable RubotState snapshots"
# validation = "Raises InvalidRubotSizeError if rubot class has invalid size"
# collaborators = ["Arena", "Battle", "RubotState", "RubotActor", "RubotPhysics"]
#
# [callback_methods]
# call_safely = "Block-based callback with error handling"
# examples = [
#   "actor.call_safely(&:on_spawn)                                    # No args",
#   "actor.call_safely { |bot| bot.on_hit(damage: 10, direction: 45) } # With args"
# ]

module Rubowar
  class LocalActor
    include RubotActor
    include RubotPhysics
    extend Forwardable

    attr_reader :rubot_class, :instance

    def_delegators :@instance, :act, :rubot_state=, :arena_state=, :_pending_energy_spend=
    def_delegator :@instance, :actions, :rubot_actions

    def initialize(rubot_class)
      # Validate size before setting any instance variables to avoid partial initialization
      size = rubot_class.size
      validate_size!(size, rubot_class)

      @rubot_class = rubot_class
      @instance = rubot_class.new
      initialize_actor(size:)
    end

    # Reset the rubot's actions hash for a new chronon
    def reset_actions
      @instance.actions = { sense: [], move: [], combat: [] }
    end

    # Set sensing results on the rubot instance (encapsulates internal access)
    # Results are wrapped in structured Data classes for better API ergonomics.
    # @param probe [Hash, nil] Probe result to set (wrapped in ProbeEcho)
    # @param scan [Array, nil] Scan results to set (wrapped in ScanEcho)
    # @param pulse [Array, nil] Pulse results to set (wrapped in PulseEcho)
    # @param detect [Hash, nil] Detect results to set (wrapped in DetectIntel)
    def set_sensing_results(probe: nil, scan: nil, pulse: nil, detect: nil)
      @instance.probe_echo = ProbeEcho.from_hash(probe) unless probe.nil?
      @instance.scan_echo = ScanEcho.new(scan) unless scan.nil?
      @instance.pulse_echo = PulseEcho.new(pulse) unless pulse.nil?
      @instance.detect_intel = DetectIntel.from_hash(detect) unless detect.nil?
    end

    # Safely execute a block with the rubot instance, penalizing errors with damage.
    # Includes timeout protection to prevent infinite loops or excessive computation.
    #
    # @yield [instance] Block receives the rubot instance
    # @return [Object, nil] Block return value or nil on error/dead/timeout
    #
    # @example
    #   actor.call_safely { |bot| bot.on_hit(damage: 10, direction: 45) }
    #   actor.call_safely { |bot| bot.on_collision(other_state) }
    def call_safely
      return nil unless alive?

      Timeout.timeout(Config::Battle::CALLBACK_TIMEOUT) do
        yield @instance
      end
    rescue Timeout::Error
      apply_collision_damage(Config::Battle::ERROR_DAMAGE)
      warn "[#{@rubot_class.name}] Callback timed out after #{Config::Battle::CALLBACK_TIMEOUT}s"
      nil
    rescue StandardError => e
      apply_collision_damage(Config::Battle::ERROR_DAMAGE)
      warn "[#{@rubot_class.name}] Error in callback: #{e.class} - #{e.message}"
      nil
    end

    # Call on_death callback for dead rubots.
    # Unlike call_safely, this doesn't check alive? since it's meant for death callbacks.
    # Errors are logged but don't apply damage (actor is already dead).
    def call_on_death
      @instance.on_death if @instance.respond_to?(:on_death)
    rescue StandardError => e
      warn "[#{@rubot_class.name}] Error in on_death callback: #{e.class} - #{e.message}"
      nil
    end
  end
end
