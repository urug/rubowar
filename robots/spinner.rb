# frozen_string_literal: true

# A stationary rubot that spins its turret and fires when it sees something.
class Spinner
  include Rubowar::Rubot

  size :medium

  def tick
    turret(10)

    target = look
    fire(10) if target && energy > 20
  end
end
