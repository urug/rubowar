# frozen_string_literal: true

# [file]
# purpose = "Main entry point for the Rubowar rubot battle arena game"
# responsibility = "Load all components and define top-level namespace"
# pattern = "Library Entry Point"
#
# [module.Rubowar]
# purpose = "Top-level namespace for all game components"
# components = [
#   "Arena - Physics engine handling movement, collisions, bullets",
#   "Battle - Game loop orchestration and event emission",
#   "Rubot - Module players include in their rubot classes",
#   "SimpleTargeting - Optional mixin for target tracking and aiming",
#   "RubotRunner - Internal mutable state tracker for game engine",
#   "RubotState/ArenaState - Immutable Data objects for state snapshots",
#   "Bullet - Projectile tracking",
#   "Energon - Collectible energy pickups"
# ]

require_relative "rubowar/version"
require_relative "rubowar/config"
require_relative "rubowar/rubot_state"
require_relative "rubowar/arena_state"
require_relative "rubowar/rubot_runner"
require_relative "rubowar/sensing_costs"
require_relative "rubowar/rubot"
require_relative "rubowar/simple_targeting"
require_relative "rubowar/bullet"
require_relative "rubowar/energon"
require_relative "rubowar/arena"
require_relative "rubowar/battle"
require_relative "rubowar/renderers/terminal"

module Rubowar
  class Error < StandardError; end

  class ConfigurationError < Error; end
  class InvalidDimensionsError < ConfigurationError; end
  class InvalidFrictionError < ConfigurationError; end
  class InvalidTickLimitError < ConfigurationError; end
  class InsufficientRubotsError < ConfigurationError; end
  class SpawnError < ConfigurationError; end
end
