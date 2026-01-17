# frozen_string_literal: true

require "test_helper"
require "fileutils"

# Stationary bot for testing
class HtmlCanvasTestBot
  include Rubowar::Rubot
  size :medium
  def act; end
end

describe Rubowar::Renderers::HtmlCanvas do
  describe "initialization" do
    it "stores battle reference" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)

      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)

      _(renderer.instance_variable_get(:@battle)).must_equal battle
    end

    it "stores arena reference" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)

      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)

      _(renderer.instance_variable_get(:@arena)).must_equal battle.arena
    end

    it "initializes empty frames array" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)

      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)

      _(renderer.frames).must_equal []
    end

    it "uses default output directory" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)

      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)

      _(renderer.instance_variable_get(:@output_dir)).must_equal "battle-logs"
    end

    it "accepts custom output directory" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)

      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "custom-logs")

      _(renderer.instance_variable_get(:@output_dir)).must_equal "custom-logs"
    end

    it "initializes filepath as nil" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)

      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)

      _(renderer.filepath).must_be_nil
    end
  end

  describe "#render" do
    it "collects frames in memory" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      _(renderer.frames.length).must_equal 1
    end

    it "creates frame with type tick" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 5, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      _(renderer.frames.first[:type]).must_equal "tick"
    end

    it "includes chronon number in frame" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 42, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      _(renderer.frames.first[:chronon]).must_equal 42
    end

    it "includes rubots array with actor data" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      _(renderer.frames.first[:rubots].length).must_equal 2
    end

    it "includes rubot position in frame" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].x = 123.456
      battle.arena.actors[0].y = 789.012
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      rubot = renderer.frames.first[:rubots].first
      _(rubot[:x]).must_equal 123.46
      _(rubot[:y]).must_equal 789.01
    end

    it "includes rubot turret angle" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].turret_angle = 45.678
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      rubot = renderer.frames.first[:rubots].first
      _(rubot[:turret_angle]).must_equal 45.68
    end

    it "includes rubot health and max_health" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].health = 75
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      rubot = renderer.frames.first[:rubots].first
      _(rubot[:health]).must_equal 75
      _(rubot[:max_health]).must_equal 100
    end

    it "includes rubot radius based on size" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      rubot = renderer.frames.first[:rubots].first
      _(rubot[:radius]).must_equal 20
    end

    it "includes rubot alive status" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.actors[0].health = 0
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      rubots = renderer.frames.first[:rubots]
      _(rubots[0][:alive]).must_equal false
      _(rubots[1][:alive]).must_equal true
    end

    it "includes bullets in frame" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      bullets = [{ x: 100.0, y: 200.0, velocity_x: 5.0, velocity_y: 3.0 }]
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: bullets }

      renderer.render(tick_state)

      bullet = renderer.frames.first[:bullets].first
      _(bullet[:x]).must_equal 100.0
      _(bullet[:y]).must_equal 200.0
      _(bullet[:velocity_x]).must_equal 5.0
      _(bullet[:velocity_y]).must_equal 3.0
    end

    it "includes energons in frame" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      battle.arena.energons << Rubowar::Energon.spawn(x: 300.0, y: 400.0, spawn_chronon: 5)
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle)
      tick_state = { chronon: 10, actors: battle.arena.actors.map(&:to_state), bullets: [] }

      renderer.render(tick_state)

      energon = renderer.frames.first[:energons].first
      _(energon[:x]).must_equal 300.0
      _(energon[:y]).must_equal 400.0
      _(energon[:value]).must_be :>, 0
    end
  end

  describe "#render_final" do
    it "adds summary frame to frames" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      winner = battle.arena.actors.first

      renderer.render_final(winner)

      _(renderer.frames.last[:type]).must_equal "summary"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "includes winner data when winner exists" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      winner = battle.arena.actors.first

      renderer.render_final(winner)

      _(renderer.frames.last[:winner]).wont_be_nil
      _(renderer.frames.last[:winner][:name]).must_equal "HtmlCanvasTestBot"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "sets winner to nil for draw" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)

      _(renderer.frames.last[:winner]).must_be_nil
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "sets outcome to victory when winner" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      winner = battle.arena.actors.first

      renderer.render_final(winner)

      _(renderer.frames.last[:outcome]).must_equal "victory"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "sets outcome to draw when no winner" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)

      _(renderer.frames.last[:outcome]).must_equal "draw"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "writes HTML file to output directory" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)

      _(File.exist?(renderer.filepath)).must_equal true
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "creates output directory if missing" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      output_dir = "tmp/test-battle-logs-#{Time.now.to_i}"
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: output_dir)

      renderer.render_final(nil)

      _(Dir.exist?(output_dir)).must_equal true
      FileUtils.rm_rf(output_dir)
    end

    it "sets filepath after writing" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)

      _(renderer.filepath).wont_be_nil
      _(renderer.filepath).must_match(/\.html$/)
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "generates filename with timestamp and rubot names" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)

      _(renderer.filepath).must_match(/battle-\d{8}-\d{6}-htmlcanvastestbot-vs-htmlcanvastestbot\.html/)
      FileUtils.rm_rf("tmp/test-battle-logs")
    end
  end

  describe "HTML output" do
    it "generates valid HTML document" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }
      renderer.render(tick_state)

      renderer.render_final(nil)
      content = File.read(renderer.filepath)

      _(content).must_include "<!DOCTYPE html>"
      _(content).must_include "<html"
      _(content).must_include "</html>"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "embeds frame data as JSON" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      tick_state = { chronon: 1, actors: battle.arena.actors.map(&:to_state), bullets: [] }
      renderer.render(tick_state)

      renderer.render_final(nil)
      content = File.read(renderer.filepath)

      _(content).must_include "const FRAMES ="
      _(content).must_include "const METADATA ="
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "includes arena dimensions in metadata" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1, width: 800, height: 600)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)
      content = File.read(renderer.filepath)

      _(content).must_include '"width":800'
      _(content).must_include '"height":600'
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "includes CSS styles" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)
      content = File.read(renderer.filepath)

      _(content).must_include "<style>"
      _(content).must_include "#arena-canvas"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "includes JavaScript player code" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)
      content = File.read(renderer.filepath)

      _(content).must_include "class BattlePlayer"
      _(content).must_include "requestAnimationFrame"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "includes playback controls" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 1)
      battle.spawn_rubots
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")

      renderer.render_final(nil)
      content = File.read(renderer.filepath)

      _(content).must_include 'id="btn-play-pause"'
      _(content).must_include 'id="scrubber"'
      _(content).must_include 'id="speed-select"'
      FileUtils.rm_rf("tmp/test-battle-logs")
    end
  end

  describe "integration with Battle" do
    it "records full battle when used with chronon callback" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 3)
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      battle.on(:chronon) { |data| renderer.render(data) }
      battle.on(:battle_end) { |data| renderer.render_final(data[:winner]) }

      battle.run

      _(renderer.frames.length).must_equal 4
      _(renderer.frames[0][:type]).must_equal "tick"
      _(renderer.frames[1][:type]).must_equal "tick"
      _(renderer.frames[2][:type]).must_equal "tick"
      _(renderer.frames[3][:type]).must_equal "summary"
      FileUtils.rm_rf("tmp/test-battle-logs")
    end

    it "produces viewable HTML file for entire battle" do
      battle = Rubowar::Battle.local([HtmlCanvasTestBot, HtmlCanvasTestBot], chronon_limit: 2)
      renderer = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "tmp/test-battle-logs")
      battle.on(:chronon) { |data| renderer.render(data) }
      battle.on(:battle_end) { |data| renderer.render_final(data[:winner]) }

      battle.run

      _(File.exist?(renderer.filepath)).must_equal true
      content = File.read(renderer.filepath)
      _(content.length).must_be :>, 1000
      FileUtils.rm_rf("tmp/test-battle-logs")
    end
  end
end
