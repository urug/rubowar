# frozen_string_literal: true

require_relative "../test_helper"
require "prop_check"

# Property-based tests for Rubowar::Physics. These complement the example-based
# tests by exercising the input space across many random cases.
#
# Physics is a pure-math helper layer: NaN-in / NaN-out is acceptable. Engine
# seams (RubotActor, Arena, NumericValidation) are responsible for keeping
# non-finite values out of the physics layer; those guards are tested elsewhere.
class PhysicsPropertiesTest < Minitest::Test
  G = PropCheck::Generators

  # ----- distance -----

  def test_distance_is_symmetric_for_finite_inputs
    finite = G.float.where(&:finite?)
    PropCheck.forall(finite, finite, finite, finite) do |x1, y1, x2, y2|
      d1 = Rubowar::Physics.distance(x1:, y1:, x2:, y2:)
      d2 = Rubowar::Physics.distance(x1: x2, y1: y2, x2: x1, y2: y1)
      assert_equal d1, d2
    end
  end

  def test_distance_is_non_negative_for_finite_inputs
    finite = G.float.where(&:finite?)
    PropCheck.forall(finite, finite, finite, finite) do |x1, y1, x2, y2|
      d = Rubowar::Physics.distance(x1:, y1:, x2:, y2:)
      assert d >= 0, "distance was #{d}"
    end
  end

  # ----- mass_factor -----

  # Constrained to the game's working range (radii in Config::Rubot::SIZES are
  # 8–20). Below ~1e-154, (radius/medium)**2 underflows to zero — a Float
  # limitation, not a bug, since real radii come from config not player input.
  def test_mass_factor_positive_for_realistic_radius
    realistic = G.float.where { |f| f.finite? && f >= 0.01 && f < 1000 }
    PropCheck.forall(realistic) do |r|
      m = Rubowar::Physics.mass_factor(r)
      assert m > 0, "mass_factor(#{r}) = #{m}"
    end
  end

  # ----- normalize_angle -----

  def test_normalize_angle_in_range_for_finite_input
    PropCheck.forall(G.float.where(&:finite?)) do |angle|
      result = Rubowar::Physics.normalize_angle(angle)
      assert result >= -180 && result <= 180,
             "normalize_angle(#{angle}) = #{result}"
      refute_equal(-180, result, "normalize_angle should never return -180")
    end
  end

  # ----- separation_direction -----

  def test_separation_direction_returns_unit_vector
    finite_nonzero = G.float.where { |f| f.finite? && f.abs > 1e-6 && f.abs < 1e6 }
    PropCheck.forall(finite_nonzero, finite_nonzero, finite_nonzero, finite_nonzero) do |ax, ay, bx, by|
      distance = Rubowar::Physics.distance(x1: ax, y1: ay, x2: bx, y2: by)
      next if distance < 1e-9

      dx, dy = Rubowar::Physics.separation_direction(
        a_x: ax, a_y: ay, b_x: bx, b_y: by, distance:,
        a_vx: 0.0, a_vy: 0.0, b_vx: 0.0, b_vy: 0.0
      )
      magnitude = Math.sqrt((dx**2) + (dy**2))
      assert_in_delta 1.0, magnitude, 1e-9,
                      "separation_direction not unit: (#{dx}, #{dy}) magnitude=#{magnitude}"
    end
  end

  # ----- collision_bounce conserves momentum -----

  def test_collision_bounce_conserves_momentum
    bounded = G.float.where { |f| f.finite? && f.abs < 1000 }
    radius = G.float.where { |f| f.finite? && f > 0.1 && f < 100 }
    PropCheck.forall(bounded, bounded, bounded, bounded, radius, radius) do |avx, avy, bvx, bvy, ra, rb|
      mass_a = Rubowar::Physics.mass_factor(ra)
      mass_b = Rubowar::Physics.mass_factor(rb)
      nx = 1.0
      ny = 0.0

      result = Rubowar::Physics.collision_bounce(
        a_vx: avx, a_vy: avy, b_vx: bvx, b_vy: bvy,
        nx:, ny:, mass_a:, mass_b:
      )

      px_before = (mass_a * avx) + (mass_b * bvx)
      py_before = (mass_a * avy) + (mass_b * bvy)
      px_after  = (mass_a * (avx + result[:a_vx])) + (mass_b * (bvx + result[:b_vx]))
      py_after  = (mass_a * (avy + result[:a_vy])) + (mass_b * (bvy + result[:b_vy]))

      assert_in_delta px_before, px_after, 1e-6
      assert_in_delta py_before, py_after, 1e-6
    end
  end
end
