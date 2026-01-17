# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"

# Stationary bot for testing
class JsonLoggerTestBot
  include Rubowar::Rubot
  size :medium
  def act; end
end

describe Rubowar::Renderers::JsonLogger do
  describe "initialization" do
    it "stores battle reference" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)

      logger = Rubowar::Renderers::JsonLogger.new(battle)

      _(logger.instance_variable_get(:@battle)).must_equal battle
    end

    it "stores arena reference" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)

      logger = Rubowar::Renderers::JsonLogger.new(battle)

      _(logger.instance_variable_get(:@arena)).must_equal battle.arena
    end

    it "initializes empty frames array" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)

      logger = Rubowar::Renderers::JsonLogger.new(battle)

      _(logger.frames).must_equal []
    end

    it "accepts optional output stream" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      output = StringIO.new

      logger = Rubowar::Renderers::JsonLogger.new(battle, output: output)

      _(logger.instance_variable_get(:@output)).must_equal output
    end

    it "accepts optional pretty flag" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)

      logger = Rubowar::Renderers::JsonLogger.new(battle, pretty: true)

      _(logger.instance_variable_get(:@pretty)).must_equal true
    end
  end

  describe "#render" do
    it "collects frames in memory when no output stream" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(logger.frames.length).must_equal 1
    end

    it "writes to output stream when provided" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      output = StringIO.new
      logger = Rubowar::Renderers::JsonLogger.new(battle, output: output)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(output.string).wont_be_empty
    end

    it "creates frame with type tick" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 5, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(logger.frames.first[:type]).must_equal "tick"
    end

    it "includes chronon number in frame" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 42, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(logger.frames.first[:chronon]).must_equal 42
    end

    it "includes rubots array with actor data" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(logger.frames.first[:rubots].length).must_equal 2
    end

    it "includes rubot position in frame" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].x = 123.456
      battle.arena.actors[0].y = 789.012
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      rubot = logger.frames.first[:rubots].first
      _(rubot[:x]).must_equal 123.46
      _(rubot[:y]).must_equal 789.01
    end

    it "includes rubot name from class" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(logger.frames.first[:rubots].first[:name]).must_equal "JsonLoggerTestBot"
    end

    it "includes rubot id" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      _(logger.frames.first[:rubots].first[:id]).must_match(/^rbot-[0-9a-f]{8}$/)
    end

    it "includes rubot health stats" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].health = 75
      battle.arena.actors[0].energy = 50
      battle.arena.actors[0].shield_level = 10
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      rubot = logger.frames.first[:rubots].first
      _(rubot[:health]).must_equal 75
      _(rubot[:energy]).must_equal 50
      _(rubot[:shield_level]).must_equal 10
    end

    it "includes rubot alive status" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].health = 0
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      rubots = logger.frames.first[:rubots]
      _(rubots[0][:alive]).must_equal false
      _(rubots[1][:alive]).must_equal true
    end

    it "includes bullets in frame" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      bullets = [{ x: 100.0, y: 200.0, velocity_x: 5.0, velocity_y: 3.0 }]
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: bullets }

      logger.render(tick_state)

      bullet = logger.frames.first[:bullets].first
      _(bullet[:x]).must_equal 100.0
      _(bullet[:y]).must_equal 200.0
      _(bullet[:velocity_x]).must_equal 5.0
      _(bullet[:velocity_y]).must_equal 3.0
    end

    it "includes energons in frame" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.energons << Rubowar::Energon.spawn(x: 300.0, y: 400.0, spawn_chronon: 5)
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      tick_state = { chronon: 10, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      logger.render(tick_state)

      energon = logger.frames.first[:energons].first
      _(energon[:x]).must_equal 300.0
      _(energon[:y]).must_equal 400.0
      _(energon[:spawn_chronon]).must_equal 5
      _(energon[:current_value]).must_be :>, 0
    end
  end

  describe "#render_final" do
    it "adds summary frame to frames" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      winner = battle.arena.actors.first

      logger.render_final(winner)

      _(logger.frames.last[:type]).must_equal "summary"
    end

    it "includes winner data when winner exists" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      winner = battle.arena.actors.first

      logger.render_final(winner)

      _(logger.frames.last[:winner]).wont_be_nil
      _(logger.frames.last[:winner][:name]).must_equal "JsonLoggerTestBot"
    end

    it "sets winner to nil for draw" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      logger.render_final(nil)

      _(logger.frames.last[:winner]).must_be_nil
    end

    it "sets outcome to victory when winner" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      winner = battle.arena.actors.first

      logger.render_final(winner)

      _(logger.frames.last[:outcome]).must_equal "victory"
    end

    it "sets outcome to draw when no winner" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      logger.render_final(nil)

      _(logger.frames.last[:outcome]).must_equal "draw"
    end

    it "includes duration" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      logger.render_final(nil)

      _(logger.frames.last[:duration_ms]).must_be :>=, 0
    end

    it "writes to output stream when provided" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      output = StringIO.new
      logger = Rubowar::Renderers::JsonLogger.new(battle, output: output)

      logger.render_final(nil)

      _(output.string).wont_be_empty
      parsed = JSON.parse(output.string)
      _(parsed["type"]).must_equal "summary"
    end
  end

  describe "#to_h" do
    it "returns hash with metadata key" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      result = logger.to_h

      _(result[:metadata]).wont_be_nil
    end

    it "returns hash with frames key" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      result = logger.to_h

      _(result[:frames]).must_equal []
    end

    it "includes arena dimensions in metadata" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1, width: 800, height: 600)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      result = logger.to_h

      _(result[:metadata][:arena][:width]).must_equal 800
      _(result[:metadata][:arena][:height]).must_equal 600
    end

    it "includes rubot names in metadata" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      result = logger.to_h

      _(result[:metadata][:rubots].length).must_equal 2
      _(result[:metadata][:rubots].first[:name]).must_equal "JsonLoggerTestBot"
    end

    it "includes recorded_at timestamp in metadata" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      result = logger.to_h

      _(result[:metadata][:recorded_at]).must_match(/^\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "#to_json" do
    it "returns valid JSON string" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      json = logger.to_json

      parsed = JSON.parse(json)
      _(parsed).must_be_kind_of Hash
    end

    it "returns pretty JSON when pretty flag set" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle, pretty: true)

      json = logger.to_json

      _(json).must_include "\n"
    end

    it "returns compact JSON by default" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 1)
      battle.spawn_rubots
      logger = Rubowar::Renderers::JsonLogger.new(battle)

      json = logger.to_json

      _(json).wont_include "\n"
    end
  end

  describe "integration with Battle" do
    it "records full battle when used with chronon callback" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 3)
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      battle.on(:chronon) { |data| logger.render(data) }
      battle.on(:battle_end) { |data| logger.render_final(data[:winner]) }

      battle.run

      _(logger.frames.length).must_equal 4
      _(logger.frames[0][:type]).must_equal "tick"
      _(logger.frames[1][:type]).must_equal "tick"
      _(logger.frames[2][:type]).must_equal "tick"
      _(logger.frames[3][:type]).must_equal "summary"
    end

    it "produces parseable JSON for entire battle" do
      battle = Rubowar::Battle.local([JsonLoggerTestBot, JsonLoggerTestBot], chronon_limit: 2)
      logger = Rubowar::Renderers::JsonLogger.new(battle)
      battle.on(:chronon) { |data| logger.render(data) }
      battle.on(:battle_end) { |data| logger.render_final(data[:winner]) }

      battle.run
      json = logger.to_json

      parsed = JSON.parse(json)
      _(parsed["metadata"]).wont_be_nil
      _(parsed["frames"].length).must_equal 3
    end
  end
end
