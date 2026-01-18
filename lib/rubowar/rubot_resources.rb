# frozen_string_literal: true

# [file]
# purpose = "Resource management for rubot actors (health, energy, shields)"
# responsibility = "Track and modify health, energy, shields, and damage statistics"
# pattern = "Mixin Module"
#
# [module.RubotResources]
# purpose = "Provides resource management methods for actors"
# note = "Include in classes that also include RubotActor (which provides max_health, energy_regen)"
# dependencies = ["RubotActor (for max_health, energy_regen)", "NumericValidation", "Config"]
#
# [thread_safety]
# design = "All resource modifications are protected by @resource_mutex"
# rationale = "Concurrent act() execution may call apply_damage from worker threads on error"
#
# [methods]
# energy = ["max_energy", "regenerate_energy", "spend_energy", "add_energy"]
# shields = ["max_shield", "degrade_shield", "add_shield", "increase_shielding"]
# damage = ["apply_damage", "apply_collision_damage", "add_damage_dealt"]

module Rubowar
  module RubotResources
    # Initialize the resource mutex. Call this from initialize_actor.
    def initialize_resource_mutex
      @resource_mutex = Mutex.new
    end

    # === Resource caps ===

    def max_energy
      Config::Rubot::MAX_ENERGY
    end

    def max_shield
      max_health # Shield cap equals HP cap
    end

    # === Damage handling ===

    # Normal damage - shields absorb first
    # Thread-safe: may be called from worker threads during concurrent act() execution
    def apply_damage(amount)
      @resource_mutex.synchronize do
        if @shield_level.positive?
          absorbed = [@shield_level, amount].min
          @shield_level -= absorbed
          amount -= absorbed
        end

        @health -= amount
        @health = 0 if @health.negative?
        @damage_taken += amount
      end
    end

    # Collision damage - bypasses shields (physical impact)
    # Thread-safe: may be called from worker threads during concurrent act() execution
    def apply_collision_damage(amount)
      @resource_mutex.synchronize do
        @health -= amount
        @health = 0 if @health.negative?
        @damage_taken += amount
      end
    end

    # === Energy management ===

    def regenerate_energy
      @resource_mutex.synchronize do
        @energy = [@energy + energy_regen, max_energy].min
      end
    end

    # Attempts to spend energy. If insufficient energy, drains to zero and returns false.
    # This penalizes rubots for attempting actions they can't afford.
    def spend_energy(amount)
      NumericValidation.validate!(amount, name: "energy amount", non_negative: true)

      @resource_mutex.synchronize do
        if amount > @energy
          @energy = 0
          false
        else
          @energy -= amount
          true
        end
      end
    end

    def add_energy(amount)
      @resource_mutex.synchronize do
        @energy = [@energy + amount, max_energy].min
      end
    end

    # === Shield management ===

    def degrade_shield
      @resource_mutex.synchronize do
        @shield_level = (@shield_level * (1 - Config::Rubot::SHIELD_DECAY_RATE)).floor
      end
    end

    def add_shield(amount)
      @resource_mutex.synchronize do
        @shield_level = [@shield_level + amount, max_shield].min
      end
    end

    def increase_shielding(energy)
      NumericValidation.validate!(energy, name: "shield energy", positive: true)

      return false unless spend_energy(energy)

      add_shield(energy)
      true
    end

    # === Combat stats ===

    def add_damage_dealt(amount)
      @resource_mutex.synchronize do
        @damage_dealt += amount
      end
    end
  end
end
