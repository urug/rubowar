# frozen_string_literal: true

require "test_helper"

describe Rubowar::ProbeEcho do
  describe ".empty" do
    it "creates a probe echo with all nil fields" do
      result = Rubowar::ProbeEcho.empty

      _(result.size).must_be_nil
      _(result.x).must_be_nil
      _(result.y).must_be_nil
      _(result.velocity_x).must_be_nil
      _(result.velocity_y).must_be_nil
      _(result.turret_angle).must_be_nil
      _(result.shield_level).must_be_nil
      _(result.health).must_be_nil
      _(result.energy).must_be_nil
    end

    it "is empty" do
      _(Rubowar::ProbeEcho.empty).must_be :empty?
    end

    it "is not found" do
      _(Rubowar::ProbeEcho.empty.found?).must_equal false
    end
  end

  describe ".from_hash" do
    it "creates a probe echo from a hash with all fields" do
      result = Rubowar::ProbeEcho.from_hash(
        size: :medium, x: 100.0, y: 200.0,
        velocity_x: 1.5, velocity_y: -2.0,
        turret_angle: 45.0, shield_level: 10,
        health: 80, energy: 50
      )

      _(result.size).must_equal :medium
      _(result.x).must_equal 100.0
      _(result.y).must_equal 200.0
      _(result.velocity_x).must_equal 1.5
      _(result.velocity_y).must_equal(-2.0)
      _(result.turret_angle).must_equal 45.0
      _(result.shield_level).must_equal 10
      _(result.health).must_equal 80
      _(result.energy).must_equal 50
    end

    it "returns empty for nil hash" do
      _(Rubowar::ProbeEcho.from_hash(nil)).must_be :empty?
    end

    it "returns empty for empty hash" do
      _(Rubowar::ProbeEcho.from_hash({})).must_be :empty?
    end

    it "supports :shield alias for shield_level" do
      result = Rubowar::ProbeEcho.from_hash(shield: 25)

      _(result.shield_level).must_equal 25
    end
  end

  describe "#found?" do
    it "returns true when size is present" do
      result = Rubowar::ProbeEcho.new(
        size: :small, x: nil, y: nil, velocity_x: nil, velocity_y: nil,
        turret_angle: nil, shield_level: nil, health: nil, energy: nil
      )

      _(result.found?).must_equal true
    end

    it "returns true when position is present" do
      result = Rubowar::ProbeEcho.new(
        size: nil, x: 100, y: 200, velocity_x: nil, velocity_y: nil,
        turret_angle: nil, shield_level: nil, health: nil, energy: nil
      )

      _(result.found?).must_equal true
    end

    it "returns true when health is present" do
      result = Rubowar::ProbeEcho.new(
        size: nil, x: nil, y: nil, velocity_x: nil, velocity_y: nil,
        turret_angle: nil, shield_level: nil, health: 80, energy: nil
      )

      _(result.found?).must_equal true
    end

    it "returns false when all fields are nil" do
      _(Rubowar::ProbeEcho.empty.found?).must_equal false
    end
  end

  describe "#any?" do
    it "is an alias for found?" do
      found_result = Rubowar::ProbeEcho.new(
        size: :medium, x: nil, y: nil, velocity_x: nil, velocity_y: nil,
        turret_angle: nil, shield_level: nil, health: nil, energy: nil
      )

      _(found_result.any?).must_equal true
      _(Rubowar::ProbeEcho.empty.any?).must_equal false
    end
  end

  describe "#[]" do
    it "provides backward-compatible hash-style access" do
      result = Rubowar::ProbeEcho.new(
        size: :large, x: 50.0, y: 75.0, velocity_x: 2.0, velocity_y: 3.0,
        turret_angle: 90.0, shield_level: 20, health: 100, energy: 80
      )

      _(result[:size]).must_equal :large
      _(result[:x]).must_equal 50.0
      _(result[:y]).must_equal 75.0
      _(result[:velocity_x]).must_equal 2.0
      _(result[:velocity_y]).must_equal 3.0
      _(result[:turret_angle]).must_equal 90.0
      _(result[:shield_level]).must_equal 20
      _(result[:shield]).must_equal 20 # alias
      _(result[:health]).must_equal 100
      _(result[:energy]).must_equal 80
      _(result[:unknown_key]).must_be_nil
    end
  end
end

describe Rubowar::SenseTarget do
  describe ".from_hash" do
    it "creates a target from hash" do
      target = Rubowar::SenseTarget.from_hash(
        x: 100, y: 200, type: :rubot,
        velocity_x: 5.0, velocity_y: -3.0, owner: nil
      )

      _(target.x).must_equal 100
      _(target.y).must_equal 200
      _(target.type).must_equal :rubot
      _(target.velocity_x).must_equal 5.0
      _(target.velocity_y).must_equal(-3.0)
      _(target.owner).must_be_nil
    end
  end

  describe "#rubot?" do
    it "returns true for rubot type" do
      target = Rubowar::SenseTarget.new(x: 0, y: 0, type: :rubot, velocity_x: nil, velocity_y: nil, owner: nil)
      _(target.rubot?).must_equal true
    end

    it "returns false for bullet type" do
      target = Rubowar::SenseTarget.new(x: 0, y: 0, type: :bullet, velocity_x: nil, velocity_y: nil, owner: nil)
      _(target.rubot?).must_equal false
    end
  end

  describe "#bullet?" do
    it "returns true for bullet type" do
      target = Rubowar::SenseTarget.new(x: 0, y: 0, type: :bullet, velocity_x: nil, velocity_y: nil, owner: nil)
      _(target.bullet?).must_equal true
    end

    it "returns false for rubot type" do
      target = Rubowar::SenseTarget.new(x: 0, y: 0, type: :rubot, velocity_x: nil, velocity_y: nil, owner: nil)
      _(target.bullet?).must_equal false
    end
  end

  describe "#[]" do
    it "provides backward-compatible hash-style access" do
      target = Rubowar::SenseTarget.new(
        x: 100, y: 200, type: :bullet,
        velocity_x: 5.0, velocity_y: -3.0, owner: "TestBot"
      )

      _(target[:x]).must_equal 100
      _(target[:y]).must_equal 200
      _(target[:type]).must_equal :bullet
      _(target[:velocity_x]).must_equal 5.0
      _(target[:velocity_y]).must_equal(-3.0)
      _(target[:owner]).must_equal "TestBot"
      _(target[:unknown]).must_be_nil
    end
  end
end

describe Rubowar::ScanEcho do
  def build_rubot_target(x: 100, y: 100)
    Rubowar::SenseTarget.new(x:, y:, type: :rubot, velocity_x: nil, velocity_y: nil, owner: nil)
  end

  def build_bullet_target(x: 100, y: 100)
    Rubowar::SenseTarget.new(x:, y:, type: :bullet, velocity_x: nil, velocity_y: nil, owner: "TestBot")
  end

  describe ".empty" do
    it "creates an empty scan echo" do
      _(Rubowar::ScanEcho.empty).must_be :empty?
      _(Rubowar::ScanEcho.empty.size).must_equal 0
    end
  end

  describe "#initialize" do
    it "wraps hashes in SenseTarget objects" do
      echo = Rubowar::ScanEcho.new([{ x: 100, y: 200, type: :rubot }])

      _(echo[0]).must_be_kind_of Rubowar::SenseTarget
      _(echo[0].x).must_equal 100
    end

    it "preserves existing SenseTarget objects" do
      target = build_rubot_target
      echo = Rubowar::ScanEcho.new([target])

      _(echo[0]).must_equal target
    end
  end

  describe "#rubots" do
    it "filters to only rubots" do
      echo = Rubowar::ScanEcho.new([
                                     build_rubot_target(x: 100, y: 100),
                                     build_bullet_target(x: 200, y: 200),
                                     build_rubot_target(x: 300, y: 300)
                                   ])

      rubots = echo.rubots
      _(rubots.length).must_equal 2
      _(rubots.all?(&:rubot?)).must_equal true
    end
  end

  describe "#bullets" do
    it "filters to only bullets" do
      echo = Rubowar::ScanEcho.new([
                                     build_rubot_target(x: 100, y: 100),
                                     build_bullet_target(x: 200, y: 200),
                                     build_bullet_target(x: 300, y: 300)
                                   ])

      bullets = echo.bullets
      _(bullets.length).must_equal 2
      _(bullets.all?(&:bullet?)).must_equal true
    end
  end

  describe "#any_rubots?" do
    it "returns true when rubots present" do
      echo = Rubowar::ScanEcho.new([build_rubot_target])
      _(echo.any_rubots?).must_equal true
    end

    it "returns false when no rubots" do
      echo = Rubowar::ScanEcho.new([build_bullet_target])
      _(echo.any_rubots?).must_equal false
    end
  end

  describe "#any_bullets?" do
    it "returns true when bullets present" do
      echo = Rubowar::ScanEcho.new([build_bullet_target])
      _(echo.any_bullets?).must_equal true
    end

    it "returns false when no bullets" do
      echo = Rubowar::ScanEcho.new([build_rubot_target])
      _(echo.any_bullets?).must_equal false
    end
  end

  describe "#closest_rubot" do
    it "finds the closest rubot to a position" do
      echo = Rubowar::ScanEcho.new([
                                     build_rubot_target(x: 200, y: 100),
                                     build_rubot_target(x: 150, y: 100),
                                     build_bullet_target(x: 110, y: 100)
                                   ])

      closest = echo.closest_rubot(to_x: 100, to_y: 100)
      _(closest.x).must_equal 150
    end

    it "returns nil when no rubots" do
      echo = Rubowar::ScanEcho.new([build_bullet_target])
      _(echo.closest_rubot(to_x: 0, to_y: 0)).must_be_nil
    end
  end

  describe "#closest_bullet" do
    it "finds the closest bullet to a position" do
      echo = Rubowar::ScanEcho.new([
                                     build_bullet_target(x: 200, y: 100),
                                     build_bullet_target(x: 150, y: 100),
                                     build_rubot_target(x: 110, y: 100)
                                   ])

      closest = echo.closest_bullet(to_x: 100, to_y: 100)
      _(closest.x).must_equal 150
    end
  end

  describe "#closest" do
    it "finds the closest target of any type" do
      echo = Rubowar::ScanEcho.new([
                                     build_rubot_target(x: 200, y: 100),
                                     build_bullet_target(x: 110, y: 100)
                                   ])

      closest = echo.closest(to_x: 100, to_y: 100)
      _(closest.x).must_equal 110
      _(closest.bullet?).must_equal true
    end
  end

  describe "Enumerable" do
    it "supports each" do
      echo = Rubowar::ScanEcho.new([build_rubot_target, build_bullet_target])
      count = 0
      echo.each { count += 1 }
      _(count).must_equal 2
    end

    it "supports map" do
      echo = Rubowar::ScanEcho.new([build_rubot_target(x: 100, y: 200)])
      _(echo.map(&:x)).must_equal [100]
    end
  end
end

describe Rubowar::PulseEcho do
  def build_rubot_target(x: 100, y: 100)
    Rubowar::SenseTarget.new(x:, y:, type: :rubot, velocity_x: nil, velocity_y: nil, owner: nil)
  end

  def build_bullet_target(x: 100, y: 100)
    Rubowar::SenseTarget.new(x:, y:, type: :bullet, velocity_x: nil, velocity_y: nil, owner: "TestBot")
  end

  describe ".empty" do
    it "creates an empty pulse echo" do
      _(Rubowar::PulseEcho.empty).must_be :empty?
    end
  end

  describe "#rubots" do
    it "filters to only rubots" do
      echo = Rubowar::PulseEcho.new([build_rubot_target, build_bullet_target])
      _(echo.rubots.length).must_equal 1
      _(echo.rubots.first.rubot?).must_equal true
    end
  end

  describe "#any_rubots?" do
    it "returns true when rubots present" do
      echo = Rubowar::PulseEcho.new([build_rubot_target])
      _(echo.any_rubots?).must_equal true
    end
  end

  describe "#closest_rubot" do
    it "finds the closest rubot to a position" do
      echo = Rubowar::PulseEcho.new([
                                      build_rubot_target(x: 200, y: 100),
                                      build_rubot_target(x: 120, y: 100)
                                    ])

      closest = echo.closest_rubot(to_x: 100, to_y: 100)
      _(closest.x).must_equal 120
    end
  end
end

describe Rubowar::DetectIntel do
  describe ".empty" do
    it "creates detect intel with all zeros" do
      result = Rubowar::DetectIntel.empty

      _(result.probed).must_equal 0
      _(result.scanned).must_equal 0
      _(result.pulsed).must_equal 0
    end

    it "is empty" do
      _(Rubowar::DetectIntel.empty).must_be :empty?
    end
  end

  describe ".from_hash" do
    it "creates detect intel from hash" do
      result = Rubowar::DetectIntel.from_hash(probed: 2, scanned: 1, pulsed: 3)

      _(result.probed).must_equal 2
      _(result.scanned).must_equal 1
      _(result.pulsed).must_equal 3
    end

    it "returns empty for nil hash" do
      _(Rubowar::DetectIntel.from_hash(nil)).must_be :empty?
    end

    it "defaults missing fields to zero" do
      result = Rubowar::DetectIntel.from_hash(probed: 5)

      _(result.probed).must_equal 5
      _(result.scanned).must_equal 0
      _(result.pulsed).must_equal 0
    end
  end

  describe "#targeted?" do
    it "returns true when probed" do
      result = Rubowar::DetectIntel.new(probed: 1, scanned: 0, pulsed: 0)
      _(result.targeted?).must_equal true
    end

    it "returns true when scanned" do
      result = Rubowar::DetectIntel.new(probed: 0, scanned: 1, pulsed: 0)
      _(result.targeted?).must_equal true
    end

    it "returns true when pulsed" do
      result = Rubowar::DetectIntel.new(probed: 0, scanned: 0, pulsed: 1)
      _(result.targeted?).must_equal true
    end

    it "returns false when all zeros" do
      _(Rubowar::DetectIntel.empty.targeted?).must_equal false
    end
  end

  describe "#empty?" do
    it "returns true when not targeted" do
      _(Rubowar::DetectIntel.empty.empty?).must_equal true
    end

    it "returns false when targeted" do
      result = Rubowar::DetectIntel.new(probed: 1, scanned: 0, pulsed: 0)
      _(result.empty?).must_equal false
    end
  end

  describe "#[]" do
    it "provides backward-compatible hash-style access" do
      result = Rubowar::DetectIntel.new(probed: 2, scanned: 3, pulsed: 1)

      _(result[:probed]).must_equal 2
      _(result[:scanned]).must_equal 3
      _(result[:pulsed]).must_equal 1
      _(result[:unknown]).must_be_nil
    end
  end
end
