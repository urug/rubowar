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
#   "Phases::Sense/Move/Combat/Energon - Phase execution modules",
#   "Rubot - Module players include in their rubot classes",
#   "SimpleTargeting - Optional mixin for target tracking and aiming",
#   "RubotActor - Internal mutable state tracker for game engine",
#   "RubotState/ArenaState/CollisionResponse - Immutable Data objects",
#   "SpawnPositionCalculator - Spawn position algorithms",
#   "Bullet - Projectile tracking",
#   "Energon - Collectible energy pickups"
# ]

require_relative "rubowar/version"
require_relative "rubowar/errors"
require_relative "rubowar/numeric_validation"
require_relative "rubowar/config"
require_relative "rubowar/sensor_calculator"
require_relative "rubowar/sensing_results"
require_relative "rubowar/rubot_state"
require_relative "rubowar/arena_state"
require_relative "rubowar/rubot_actor"
require_relative "rubowar/stub_actor"
require_relative "rubowar/rubot"
require_relative "rubowar/simple_targeting"
require_relative "rubowar/bullet"
require_relative "rubowar/energon"
require_relative "rubowar/physics"
require_relative "rubowar/spawn_position_calculator"
require_relative "rubowar/collision_response"
require_relative "rubowar/collision_system"
require_relative "rubowar/arena"
require_relative "rubowar/phases/sense"
require_relative "rubowar/phases/move"
require_relative "rubowar/phases/combat"
require_relative "rubowar/phases/energon"
require_relative "rubowar/battle"
require_relative "rubowar/renderers/terminal"
