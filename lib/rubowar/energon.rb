# frozen_string_literal: true

# [file]
# purpose = "Collectible energy pickups that spawn in the arena"
# responsibility = "Track position and calculate value based on age"
# pattern = "Value Object (Data.define)"
#
# [class.Energon]
# purpose = "Energy pickup that grows more valuable over time"
# constants = { RADIUS = 8, INITIAL_VALUE = 1, GROWTH_RATE = 1.0 }
# value_formula = "INITIAL_VALUE + (chronons_alive * GROWTH_RATE)"
# collection = "Rubot touches energon -> gains value as energy"

module Rubowar
  Energon = Data.define(:x, :y, :spawn_chronon) do
    def value(current_chronon)
      chronons_alive = current_chronon - spawn_chronon
      Config::Energon::INITIAL_VALUE + (chronons_alive * Config::Energon::GROWTH_RATE)
    end

    def value_int(current_chronon)
      value(current_chronon).floor
    end
  end
end
