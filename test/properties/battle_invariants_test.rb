# frozen_string_literal: true

require_relative "../test_helper"

# Battle-level invariant: a Rubot emitting hostile action parameters every
# chronon must not be able to drive any actor's numeric state to NaN or
# Infinity. Bad values causing self-damage is fine (by design); state
# corruption is not.
class BattleInvariantsTest < Minitest::Test
  class ChaosBot
    include Rubowar::Rubot

    HOSTILE_VALUES = [
      Float::NAN, Float::INFINITY, -Float::INFINITY,
      -1e9, -1, 0, 1e-300, 1e9,
      Complex(1, 2), "string", nil
    ].freeze

    def act
      h = -> { HOSTILE_VALUES.sample }
      safe { fire(h.call) }
      safe { raise_shields(h.call) }
      safe { rotate_turret(h.call) }
      safe { thrust(speed: h.call, angle: h.call) }
      safe { scan(angle: h.call, distance: h.call) }
      safe { pulse(distance: h.call) }
    end

    private

    def safe
      yield
    rescue StandardError
      # engine-side rescue handles errors and applies damage; act() shouldn't blow up
    end
  end

  class NoOpBot
    include Rubowar::Rubot
    def act; end
  end

  def test_battle_state_stays_finite_under_chaos
    battle = Rubowar::Battle.local(
      [ChaosBot, NoOpBot, ChaosBot],
      chronon_limit: 50,
      seed: 12_345
    )

    battle.run

    battle.arena.actors.each do |actor|
      msg = "actor #{actor.name}"
      assert actor.x.finite?, "#{msg}: x=#{actor.x}"
      assert actor.y.finite?, "#{msg}: y=#{actor.y}"
      assert actor.velocity_x.finite?, "#{msg}: vx=#{actor.velocity_x}"
      assert actor.velocity_y.finite?, "#{msg}: vy=#{actor.velocity_y}"
      assert actor.turret_angle.finite?, "#{msg}: turret=#{actor.turret_angle}"
      assert actor.health.finite?, "#{msg}: health=#{actor.health}"
      assert actor.energy.finite?, "#{msg}: energy=#{actor.energy}"
      assert actor.shield_level.finite?, "#{msg}: shield=#{actor.shield_level}"
      assert actor.energy >= 0, "#{msg}: energy went negative (#{actor.energy})"
    end

    battle.arena.bullets.each do |b|
      assert b.x.finite? && b.y.finite?, "bullet at non-finite position (#{b.x}, #{b.y})"
      assert b.velocity_x.finite? && b.velocity_y.finite?,
             "bullet has non-finite velocity (#{b.velocity_x}, #{b.velocity_y})"
    end
  end
end
