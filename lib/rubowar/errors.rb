# frozen_string_literal: true

# [file]
# purpose = "Custom error classes for the Rubowar game engine"
# responsibility = "Define exception types for configuration and gameplay errors"
# pattern = "Exception Hierarchy"
#
# [hierarchy]
# Error = "Base class for all Rubowar errors"
# ConfigurationError = "Errors in battle/arena configuration"
#   - InvalidChrononLimitError, InsufficientRubotsError
#   - InvalidRubotSizeError, InvalidSpawnConstraintsError
# GameplayError = "Errors during gameplay execution"
#   - SpawnError, InvalidActionError, CallbackError

module Rubowar
  # Base error class for all Rubowar exceptions
  class Error < StandardError; end

  # Configuration errors (invalid setup parameters)
  class ConfigurationError < Error; end
  class InvalidChrononLimitError < ConfigurationError; end
  class InsufficientRubotsError < ConfigurationError; end
  class InvalidRubotSizeError < ConfigurationError; end
  class InvalidSpawnConstraintsError < ConfigurationError; end

  # Gameplay errors (runtime issues)
  class GameplayError < Error; end
  class SpawnError < GameplayError; end

  # Action parameter errors (invalid action parameters from rubots)
  class InvalidActionError < GameplayError; end

  # Event callback errors (one or more callbacks failed during emit)
  class CallbackError < GameplayError
    attr_reader :event_type, :errors

    def initialize(event_type, errors)
      @event_type = event_type
      @errors = errors
      messages = errors.map { |e| "#{e.class}: #{e.message}" }.join("; ")
      super("#{errors.size} callback(s) failed for :#{event_type}: #{messages}")
    end
  end
end
