# frozen_string_literal: true

require "test_helper"

describe Rubowar::Energon do
  describe "initialization" do
    it "stores x position" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      _(energon.x).must_equal 100.0
    end

    it "stores y position" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      _(energon.y).must_equal 200.0
    end

    it "stores spawn chronon" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      _(energon.spawn_chronon).must_equal 50
    end
  end

  describe "#value" do
    it "returns initial value at spawn chronon" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      _(energon.value(50)).must_equal Rubowar::Config::Energon::INITIAL_VALUE
    end

    it "increases by growth rate per chronon" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)
      growth_rate = Rubowar::Config::Energon::GROWTH_RATE

      value_at_60 = energon.value(60)

      # 10 chronons alive * growth_rate + initial_value
      expected = Rubowar::Config::Energon::INITIAL_VALUE + (10 * growth_rate)
      _(value_at_60).must_equal expected
    end

    it "returns higher value after more time" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      value_at_100 = energon.value(100)
      value_at_200 = energon.value(200)

      _(value_at_200).must_be :>, value_at_100
    end
  end

  describe "#value_int" do
    it "returns floored integer value" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      result = energon.value_int(55)

      _(result).must_be_kind_of Integer
    end

    it "floors fractional values" do
      energon = Rubowar::Energon.spawn(x: 100.0, y: 200.0, spawn_chronon: 50)

      # At chronon 51, value = 1 + (1 * 1.0) = 2.0
      # With INITIAL_VALUE=1, GROWTH_RATE=1.0
      result = energon.value_int(51)

      _(result).must_equal energon.value(51).floor
    end
  end
end
