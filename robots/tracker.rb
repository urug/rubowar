# frozen_string_literal: true

# A more sophisticated rubot that moves around, looks for enemies, and fires.
class Tracker
  include Rubowar::Rubot

  size :small

  WALL_BUFFER = 80

  def on_spawn
    @heading = rand(360)
    @turn_direction = 1
  end

  def tick
    avoid_walls
    patrol
    look_and_fire
  end

  def on_hit(_damage, direction)
    # Boost perpendicular to incoming fire
    thrust(speed: 5, angle: direction + 90)
  end

  def on_wall
    @turn_direction *= -1
    @heading = (@heading + 180) % 360
  end

  private

  def avoid_walls
    near_wall = x < WALL_BUFFER || x > arena_width - WALL_BUFFER ||
                y < WALL_BUFFER || y > arena_height - WALL_BUFFER

    @heading = (@heading + 45 * @turn_direction) % 360 if near_wall
  end

  def patrol
    @heading = (@heading + 5 * @turn_direction) % 360 if rand < 0.05
    thrust(speed: 3, angle: @heading) if speed < 4
  end

  def look_and_fire
    target = look(:velocity)

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
