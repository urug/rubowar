# frozen_string_literal: true

# [file]
# purpose = "Numeric parameter validation for Arena/engine code"
# responsibility = "Reject NaN, Infinity, and out-of-range values"
# pattern = "Module Functions (stateless validation)"
#
# [module.NumericValidation]
# purpose = "Validate numeric parameters at execution time"
# note = "NOT used in Rubot module - player errors there cause damage (learning opportunity)"
# usage = "NumericValidation.validate!(value, name: 'param', positive: true)"

module Rubowar
  module NumericValidation
    module_function

    # Validates a numeric parameter, rejecting NaN, Infinity, and out-of-range values.
    # Raises InvalidActionError for player-caused issues (action parameters).
    #
    # @param value [Object] The value to validate
    # @param name [String] Parameter name for error messages
    # @param positive [Boolean] If true, value must be > 0
    # @param non_negative [Boolean] If true, value must be >= 0
    # @param max [Numeric, nil] Maximum allowed value (inclusive)
    # @return [Numeric] The validated value
    # @raise [InvalidActionError] If validation fails
    def validate!(value, name:, positive: false, non_negative: false, max: nil)
      unless value.is_a?(Numeric)
        raise InvalidActionError, "#{name} must be a number, got #{value.class}"
      end

      if value.respond_to?(:nan?) && value.nan?
        raise InvalidActionError, "#{name} cannot be NaN"
      end

      if value.respond_to?(:infinite?) && value.infinite?
        raise InvalidActionError, "#{name} cannot be Infinity"
      end

      if positive && value <= 0
        raise InvalidActionError, "#{name} must be positive, got #{value}"
      end

      if non_negative && value.negative?
        raise InvalidActionError, "#{name} must be non-negative, got #{value}"
      end

      if max && value > max
        raise InvalidActionError, "#{name} must be <= #{max}, got #{value}"
      end

      value
    end
  end
end
