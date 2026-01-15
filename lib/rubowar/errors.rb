# frozen_string_literal: true

# [file]
# purpose = "Custom error classes for the Rubowar game engine"
# responsibility = "Define exception types for configuration and gameplay errors"
# pattern = "Exception Hierarchy"
#
# [hierarchy]
# Error = "Base class for all Rubowar errors"
# ConfigurationError = "Errors in battle/arena configuration"
#   - InvalidDimensionsError, InvalidFrictionError, InvalidChrononLimitError
#   - InsufficientRubotsError, InvalidRubotSizeError, InvalidSpawnConstraintsError
# GameplayError = "Errors during gameplay execution"
#   - SpawnError, InvalidActionError

module Rubowar
  # Base error class for all Rubowar exceptions
  class Error < StandardError; end

  # Configuration errors (invalid setup parameters)
  class ConfigurationError < Error; end
  class InvalidDimensionsError < ConfigurationError; end
  class InvalidFrictionError < ConfigurationError; end
  class InvalidChrononLimitError < ConfigurationError; end
  class InsufficientRubotsError < ConfigurationError; end
  class InvalidRubotSizeError < ConfigurationError; end
  class InvalidSpawnConstraintsError < ConfigurationError; end

  # Gameplay errors (runtime issues)
  class GameplayError < Error; end
  class SpawnError < GameplayError; end

  # Action parameter errors (invalid action parameters from rubots)
  class InvalidActionError < GameplayError; end
end
