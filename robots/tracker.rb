# frozen_string_literal: true

# A more sophisticated rubot that moves around, looks for enemies, and fires.
class Tracker
  include Rubowar::Rubot

  size :small

  WALL_BUFFER = 80

  def on_spawn
    @direction = 1
  end

  def tick
    avoid_walls
    patrol
    look_and_fire
  end

  def on_hit(_damage, direction)
    # Turn perpendicular to incoming fire and boost away
    turn(direction + 90)
    thrust(10)
  end

  def on_wall
    @direction *= -1
  end

  private

  def avoid_walls
    near_wall = x < WALL_BUFFER || x > arena_width - WALL_BUFFER ||
                y < WALL_BUFFER || y > arena_height - WALL_BUFFER

    turn(45 * @direction) if near_wall
  end

  def patrol
    turn(5 * @direction) if rand < 0.05
    thrust(2) if speed < 4
  end

  def look_and_fire
    target = look(2)

    if target
      # Lock on - don't rotate, just fire
      fire(8) if energy > 30
      shield(5) if energy > 50 && shield_level < 20
    else
      # Search - rotate turret
      turret(8)
    end
  end
end
