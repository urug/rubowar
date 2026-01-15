# frozen_string_literal: true

# [file]
# purpose = "Structured result objects for sensing actions"
# responsibility = "Provide clean API for probe, scan, pulse, detect results"
# pattern = "Data Objects with helper methods"
#
# [design]
# immutability = "All results are immutable (Data.define or frozen arrays)"
# nil_safety = "Empty results returned instead of nil - no safe navigation needed"
# backward_compat = "Support [] access for hash-style lookups during transition"

module Rubowar
  # Result from probe() - single target detection along turret line
  # All fields are nil if no target found or attribute not requested
  ProbeEcho = Data.define(
    :size,         # :small, :medium, :large
    :x, :y,        # position (if :position requested)
    :velocity_x, :velocity_y,  # velocity (if :velocity requested)
    :turret_angle, # turret direction (if :turret_angle requested)
    :shield_level, # shield amount (if :shield requested)
    :health,       # current HP (if :health requested)
    :energy        # current energy (if :energy requested)
  ) do
    # Was a target found? Check if any attribute is present (not just size)
    def found?
      !size.nil? || !x.nil? || !velocity_x.nil? || !turret_angle.nil? ||
        !shield_level.nil? || !health.nil? || !energy.nil?
    end

    # No target found?
    def empty?
      !found?
    end

    # Alias for common pattern
    def any?
      found?
    end

    # Backward compatibility: probe_echo[:x], probe_echo[:size], etc.
    def [](key)
      case key
      when :size then size
      when :x then x
      when :y then y
      when :velocity_x then velocity_x
      when :velocity_y then velocity_y
      when :turret_angle then turret_angle
      when :shield_level, :shield then shield_level
      when :health then health
      when :energy then energy
      else nil
      end
    end

    # Create empty probe result
    def self.empty
      new(size: nil, x: nil, y: nil, velocity_x: nil, velocity_y: nil,
          turret_angle: nil, shield_level: nil, health: nil, energy: nil)
    end

    # Create from hash (for internal use)
    def self.from_hash(hash)
      return empty if hash.nil? || hash.empty?

      new(
        size: hash[:size],
        x: hash[:x],
        y: hash[:y],
        velocity_x: hash[:velocity_x],
        velocity_y: hash[:velocity_y],
        turret_angle: hash[:turret_angle],
        shield_level: hash[:shield_level] || hash[:shield],
        health: hash[:health],
        energy: hash[:energy]
      )
    end
  end

  # Individual target in scan/pulse results
  SenseTarget = Data.define(:x, :y, :type, :velocity_x, :velocity_y, :owner) do
    def rubot?
      type == :rubot
    end

    def bullet?
      type == :bullet
    end

    # Backward compatibility: target[:x], target[:type], etc.
    def [](key)
      case key
      when :x then x
      when :y then y
      when :type then type
      when :velocity_x then velocity_x
      when :velocity_y then velocity_y
      when :owner then owner
      else nil
      end
    end

    def self.from_hash(hash)
      new(
        x: hash[:x],
        y: hash[:y],
        type: hash[:type],
        velocity_x: hash[:velocity_x],
        velocity_y: hash[:velocity_y],
        owner: hash[:owner]
      )
    end
  end

  # Result from scan() - multiple targets in arc from turret direction
  class ScanEcho
    include Enumerable

    def initialize(targets = [])
      @targets = targets.map do |t|
        t.is_a?(SenseTarget) ? t : SenseTarget.from_hash(t)
      end.freeze
      freeze
    end

    def each(&block)
      @targets.each(&block)
    end

    def empty?
      @targets.empty?
    end

    def size
      @targets.size
    end
    alias length size

    def [](index)
      @targets[index]
    end

    # Filter to only rubots (returns frozen array)
    def rubots
      @targets.select(&:rubot?).freeze
    end

    # Filter to only bullets (returns frozen array)
    def bullets
      @targets.select(&:bullet?).freeze
    end

    # Quick checks
    def any_rubots?
      @targets.any?(&:rubot?)
    end

    def any_bullets?
      @targets.any?(&:bullet?)
    end

    # Find closest rubot to a position
    def closest_rubot(to_x:, to_y:)
      rubots.min_by { |t| Math.sqrt(((t.x - to_x)**2) + ((t.y - to_y)**2)) }
    end

    # Find closest bullet to a position
    def closest_bullet(to_x:, to_y:)
      bullets.min_by { |t| Math.sqrt(((t.x - to_x)**2) + ((t.y - to_y)**2)) }
    end

    # Find closest target (any type) to a position
    def closest(to_x:, to_y:)
      @targets.min_by { |t| Math.sqrt(((t.x - to_x)**2) + ((t.y - to_y)**2)) }
    end

    def self.empty
      new([])
    end
  end

  # Result from pulse() - multiple targets in radius around rubot
  # Same structure as ScanEcho but separate class for clarity
  class PulseEcho
    include Enumerable

    def initialize(targets = [])
      @targets = targets.map do |t|
        t.is_a?(SenseTarget) ? t : SenseTarget.from_hash(t)
      end.freeze
      freeze
    end

    def each(&block)
      @targets.each(&block)
    end

    def empty?
      @targets.empty?
    end

    def size
      @targets.size
    end
    alias length size

    def [](index)
      @targets[index]
    end

    # Filter to only rubots (returns frozen array)
    def rubots
      @targets.select(&:rubot?).freeze
    end

    # Filter to only bullets (returns frozen array)
    def bullets
      @targets.select(&:bullet?).freeze
    end

    # Quick checks
    def any_rubots?
      @targets.any?(&:rubot?)
    end

    def any_bullets?
      @targets.any?(&:bullet?)
    end

    # Find closest rubot to a position
    def closest_rubot(to_x:, to_y:)
      rubots.min_by { |t| Math.sqrt(((t.x - to_x)**2) + ((t.y - to_y)**2)) }
    end

    # Find closest bullet to a position
    def closest_bullet(to_x:, to_y:)
      bullets.min_by { |t| Math.sqrt(((t.x - to_x)**2) + ((t.y - to_y)**2)) }
    end

    # Find closest target (any type) to a position
    def closest(to_x:, to_y:)
      @targets.min_by { |t| Math.sqrt(((t.x - to_x)**2) + ((t.y - to_y)**2)) }
    end

    def self.empty
      new([])
    end
  end

  # Result from detect() - counter-intelligence on who sensed you
  DetectIntel = Data.define(:probed, :scanned, :pulsed) do
    # Was this rubot targeted by any sensing action?
    def targeted?
      probed.positive? || scanned.positive? || pulsed.positive?
    end

    # No one sensed us?
    def empty?
      !targeted?
    end

    # Backward compatibility: detect_intel[:probed], etc.
    def [](key)
      case key
      when :probed then probed
      when :scanned then scanned
      when :pulsed then pulsed
      else nil
      end
    end

    def self.empty
      new(probed: 0, scanned: 0, pulsed: 0)
    end

    def self.from_hash(hash)
      return empty if hash.nil?

      new(
        probed: hash[:probed] || 0,
        scanned: hash[:scanned] || 0,
        pulsed: hash[:pulsed] || 0
      )
    end
  end
end
