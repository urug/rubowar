# frozen_string_literal: true

require "json"

# [file]
# purpose = "JSON renderer for logging battle data to files or streams"
# responsibility = "Serialize battle state to structured JSON for replay/analysis"
# pattern = "Renderer / Logger"
#
# [class.JsonLogger]
# purpose = "Outputs battle state as JSON for post-battle analysis, replays, or ML training"
# input = "Battle instance and tick_state from chronon events"
# output = "JSON objects with complete battle state"
#
# [output_modes]
# stream = "Write JSON lines (NDJSON) to IO stream for real-time logging"
# array = "Collect frames in memory, output complete JSON array at end"

module Rubowar
  module Renderers
    class JsonLogger
      attr_reader :frames

      # @param battle [Battle] The battle instance
      # @param output [IO, nil] IO stream to write to (nil = collect in memory)
      # @param pretty [Boolean] Pretty-print JSON output
      def initialize(battle, output: nil, pretty: false)
        @battle = battle
        @arena = battle.arena
        @output = output
        @pretty = pretty
        @frames = []
        @start_time = Time.now
      end

      def render(tick_state)
        frame = build_frame(tick_state)

        if @output
          write_line(frame)
        else
          @frames << frame
        end
      end

      def render_final(winner)
        summary = build_summary(winner)

        if @output
          write_line(summary)
        else
          @frames << summary
        end
      end

      # Returns the complete battle log as a hash
      def to_h
        {
          metadata: build_metadata,
          frames: @frames
        }
      end

      # Returns the complete battle log as JSON
      def to_json(*args)
        if @pretty
          JSON.pretty_generate(to_h, *args)
        else
          JSON.generate(to_h, *args)
        end
      end

      private

      def build_frame(tick_state)
        {
          type: "tick",
          chronon: tick_state[:chronon],
          rubots: tick_state[:actors].each_with_index.map { |state, i| serialize_rubot_state(state, i) },
          bullets: tick_state[:bullets].map { |bullet| serialize_bullet(bullet) },
          energons: @arena.energons.map { |energon| serialize_energon(energon, tick_state[:chronon]) }
        }
      end

      def build_summary(winner)
        {
          type: "summary",
          winner: winner ? serialize_actor(winner) : nil,
          outcome: winner ? "victory" : "draw",
          duration_ms: ((Time.now - @start_time) * 1000).round
        }
      end

      def build_metadata
        {
          arena: {
            width: @arena.width,
            height: @arena.height,
            friction: @arena.friction
          },
          rubots: @battle.arena.actors.map do |actor|
            {
              name: actor.rubot_class.name,
              size: actor.size,
              id: actor.id
            }
          end,
          recorded_at: @start_time.iso8601
        }
      end

      # Serialize RubotState (from tick_state) with actor metadata
      def serialize_rubot_state(state, index)
        actor = @arena.actors[index]
        {
          id: actor.id,
          name: actor.rubot_class.name,
          x: state.x.round(2),
          y: state.y.round(2),
          velocity_x: state.velocity_x.round(2),
          velocity_y: state.velocity_y.round(2),
          speed: state.speed.round(2),
          turret_angle: state.turret_angle.round(2),
          health: state.health,
          energy: state.energy,
          shield_level: state.shield_level,
          damage_dealt: state.damage_dealt,
          damage_taken: state.damage_taken,
          size: state.size,
          alive: state.health.positive?
        }
      end

      # Serialize RubotActor (for winner in render_final)
      def serialize_actor(actor)
        {
          id: actor.id,
          name: actor.rubot_class.name,
          x: actor.x.round(2),
          y: actor.y.round(2),
          health: actor.health,
          energy: actor.energy,
          shield_level: actor.shield_level,
          damage_dealt: actor.damage_dealt,
          damage_taken: actor.damage_taken,
          size: actor.size
        }
      end

      def serialize_bullet(bullet)
        {
          x: bullet[:x].round(2),
          y: bullet[:y].round(2),
          velocity_x: bullet[:velocity_x].round(2),
          velocity_y: bullet[:velocity_y].round(2)
        }
      end

      def serialize_energon(energon, chronon)
        {
          x: energon.x.round(2),
          y: energon.y.round(2),
          spawn_chronon: energon.spawn_chronon,
          current_value: energon.value_int(chronon)
        }
      end

      def write_line(data)
        json = @pretty ? JSON.pretty_generate(data) : JSON.generate(data)
        @output.puts(json)
        @output.flush if @output.respond_to?(:flush)
      end
    end
  end
end
