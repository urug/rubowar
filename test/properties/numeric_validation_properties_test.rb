# frozen_string_literal: true

require_relative "../test_helper"
require "prop_check"

class NumericValidationPropertiesTest < Minitest::Test
  G = PropCheck::Generators

  def test_finite_values_pass_through
    PropCheck.forall(G.float.where(&:finite?)) do |v|
      assert_equal v, Rubowar::NumericValidation.validate!(v, name: "x")
    end
  end

  def test_nan_is_rejected
    assert_raises(Rubowar::InvalidActionError) do
      Rubowar::NumericValidation.validate!(Float::NAN, name: "x")
    end
  end

  def test_infinity_is_rejected
    [Float::INFINITY, -Float::INFINITY].each do |v|
      assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!(v, name: "x")
      end
    end
  end

  # Complex is_a?(Numeric) is true, so it passes the type check, but Complex
  # has no <=, so positive: true / max: ... will raise NoMethodError instead
  # of the expected InvalidActionError. Players should get a clean error, not
  # a crash.
  def test_complex_yields_invalid_action_not_no_method_error
    assert_raises(Rubowar::InvalidActionError) do
      Rubowar::NumericValidation.validate!(Complex(1, 2), name: "x", positive: true)
    end
  end

  def test_non_numeric_is_rejected
    PropCheck.forall(G.one_of(G.string, G.boolean, G.array(G.integer))) do |v|
      assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!(v, name: "x")
      end
    end
  end
end
