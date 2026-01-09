# frozen_string_literal: true

require "test_helper"

describe Rubowar::NumericValidation do
  describe ".validate!" do
    it "returns the value when valid" do
      result = Rubowar::NumericValidation.validate!(42, name: "test")

      _(result).must_equal 42
    end

    it "accepts floats" do
      result = Rubowar::NumericValidation.validate!(3.14, name: "test")

      _(result).must_equal 3.14
    end

    it "rejects non-numeric values" do
      error = assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!("foo", name: "test_param")
      end

      _(error.message).must_include "test_param"
      _(error.message).must_include "must be a number"
    end

    it "rejects nil" do
      error = assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!(nil, name: "test_param")
      end

      _(error.message).must_include "must be a number"
    end

    it "rejects NaN" do
      error = assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!(Float::NAN, name: "test_param")
      end

      _(error.message).must_include "test_param"
      _(error.message).must_include "cannot be NaN"
    end

    it "rejects positive Infinity" do
      error = assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!(Float::INFINITY, name: "test_param")
      end

      _(error.message).must_include "test_param"
      _(error.message).must_include "cannot be Infinity"
    end

    it "rejects negative Infinity" do
      error = assert_raises(Rubowar::InvalidActionError) do
        Rubowar::NumericValidation.validate!(-Float::INFINITY, name: "test_param")
      end

      _(error.message).must_include "cannot be Infinity"
    end

    describe "positive: true" do
      it "accepts positive values" do
        result = Rubowar::NumericValidation.validate!(5, name: "test", positive: true)

        _(result).must_equal 5
      end

      it "rejects zero" do
        error = assert_raises(Rubowar::InvalidActionError) do
          Rubowar::NumericValidation.validate!(0, name: "test_param", positive: true)
        end

        _(error.message).must_include "must be positive"
      end

      it "rejects negative values" do
        error = assert_raises(Rubowar::InvalidActionError) do
          Rubowar::NumericValidation.validate!(-5, name: "test_param", positive: true)
        end

        _(error.message).must_include "must be positive"
      end
    end

    describe "non_negative: true" do
      it "accepts positive values" do
        result = Rubowar::NumericValidation.validate!(5, name: "test", non_negative: true)

        _(result).must_equal 5
      end

      it "accepts zero" do
        result = Rubowar::NumericValidation.validate!(0, name: "test", non_negative: true)

        _(result).must_equal 0
      end

      it "rejects negative values" do
        error = assert_raises(Rubowar::InvalidActionError) do
          Rubowar::NumericValidation.validate!(-5, name: "test_param", non_negative: true)
        end

        _(error.message).must_include "must be non-negative"
      end
    end

    describe "max:" do
      it "accepts values below max" do
        result = Rubowar::NumericValidation.validate!(50, name: "test", max: 100)

        _(result).must_equal 50
      end

      it "accepts values equal to max" do
        result = Rubowar::NumericValidation.validate!(100, name: "test", max: 100)

        _(result).must_equal 100
      end

      it "rejects values above max" do
        error = assert_raises(Rubowar::InvalidActionError) do
          Rubowar::NumericValidation.validate!(101, name: "test_param", max: 100)
        end

        _(error.message).must_include "test_param"
        _(error.message).must_include "must be <= 100"
      end
    end
  end
end
