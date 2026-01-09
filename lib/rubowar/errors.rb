# frozen_string_literal: true

# [file]
# purpose = "Custom error classes for the Rubowar game engine"
# responsibility = "Define all exception types used throughout the codebase"
# pattern = "Exception Hierarchy"
#
# [hierarchy]
# Error = "Base class for all Rubowar errors"
# ConfigurationError = "Errors in battle/arena configuration"
# GameplayError = "Errors during gameplay execution"

module Rubowar
  # Base error class for all Rubowar exceptions
  class Error < StandardError; end

  # Configuration errors (invalid setup parameters)
  class ConfigurationError < Error; end
  class InvalidDimensionsError < ConfigurationError; end
  class InvalidFrictionError < ConfigurationError; end
  class InvalidChrononLimitError < ConfigurationError; end
  class InsufficientRubotsError < ConfigurationError; end

  # Gameplay errors (runtime issues)
  class GameplayError < Error; end
  class SpawnError < GameplayError; end
end
