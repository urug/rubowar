# frozen_string_literal: true

require "json"
require "fileutils"

# [file]
# purpose = "HTML/Canvas renderer for battle replays"
# responsibility = "Generate self-contained HTML files with animated battle visualization"
# pattern = "Renderer / Export"
#
# [class.HtmlCanvas]
# purpose = "Creates shareable HTML battle replays with Canvas animation"
# input = "Battle instance and tick_state from chronon events"
# output = "Self-contained HTML file with embedded JavaScript player"
#
# [output]
# directory = "battle-logs/ (configurable)"
# filename = "battle-{timestamp}-{rubot1}-vs-{rubot2}.html"
# features = "Play/pause, speed control, scrubbing, keyboard shortcuts"

module Rubowar
  module Renderers
    class HtmlCanvas
      attr_reader :frames, :filepath

      # @param battle [Battle] The battle instance
      # @param output_dir [String] Directory for output files (default: "battle-logs")
      def initialize(battle, output_dir: "battle-logs")
        @battle = battle
        @arena = battle.arena
        @output_dir = output_dir
        @frames = []
        @start_time = Time.now
        @filepath = nil
      end

      def render(tick_state)
        @frames << build_frame(tick_state)
      end

      def render_final(winner)
        @frames << build_summary(winner)
        @filepath = write_html_file
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
          winner: winner ? serialize_winner(winner) : nil,
          outcome: winner ? "victory" : "draw",
          total_chronons: @frames.length
        }
      end

      def build_metadata
        {
          arena: {
            width: @arena.width,
            height: @arena.height
          },
          rubots: @arena.actors.map do |actor|
            {
              id: actor.id,
              name: actor.name,
              size: actor.size
            }
          end,
          recorded_at: @start_time.iso8601
        }
      end

      def serialize_rubot_state(state, index)
        actor = @arena.actors[index]
        {
          id: actor.id,
          name: actor.name,
          x: state.x.round(2),
          y: state.y.round(2),
          turret_angle: state.turret_angle.round(2),
          health: state.health,
          max_health: actor.max_health,
          energy: state.energy,
          shield_level: state.shield_level,
          damage_dealt: state.damage_dealt,
          damage_taken: state.damage_taken,
          size: state.size,
          radius: Config::Rubot::SIZES[state.size][:radius],
          alive: state.health.positive?
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
          value: energon.value_int(chronon)
        }
      end

      def serialize_winner(actor)
        {
          name: actor.name,
          health: actor.health,
          damage_dealt: actor.damage_dealt
        }
      end

      def generate_filename
        timestamp = @start_time.strftime("%Y%m%d-%H%M%S")
        rubot_names = @arena.actors
                            .map { |a| a.name.downcase.gsub(/[^a-z0-9]/, "") }
                            .join("-vs-")
        "battle-#{timestamp}-#{rubot_names}.html"
      end

      def write_html_file
        FileUtils.mkdir_p(@output_dir)
        filepath = File.join(@output_dir, generate_filename)

        html_content = generate_html(
          metadata: build_metadata,
          frames: @frames
        )

        File.write(filepath, html_content)
        filepath
      end

      def generate_html(metadata:, frames:)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Rubowar Battle Replay</title>
            <style>
          #{css_styles}
            </style>
          </head>
          <body>
            <div id="app">
              <main id="main">
                <div id="arena-container">
                  <canvas id="arena-canvas"></canvas>
                </div>

                <aside id="status-panel">
                  <h1>Rubowar Battle Replay</h1>
                  <div id="rubot-stats"></div>
                  <div id="battle-info">
                    <span id="chronon-display">Chronon: 0</span>
                    <span id="winner-display"></span>
                  </div>
                </aside>
              </main>

              <footer id="controls">
                <button id="btn-start" title="Go to start (Home)">⏮</button>
                <button id="btn-prev" title="Previous frame (Left Arrow)">◁</button>
                <button id="btn-play-pause" title="Play/Pause (Space)">Play ▶</button>
                <button id="btn-next" title="Next frame (Right Arrow)">▷</button>
                <button id="btn-end" title="Go to end (End)">⏭</button>

                <input type="range" id="scrubber" min="0" max="0" value="0">

                <label>Speed:
                  <select id="speed-select">
                    <option value="0.5">0.5x</option>
                    <option value="1" selected>1x</option>
                    <option value="2">2x</option>
                    <option value="4">4x</option>
                    <option value="8">8x</option>
                  </select>
                </label>
              </footer>
            </div>

            <script>
          const METADATA = #{JSON.generate(metadata)};
          const FRAMES = #{JSON.generate(frames)};

          #{javascript_player}
            </script>
          </body>
          </html>
        HTML
      end

      def css_styles
        <<~CSS
          * { box-sizing: border-box; margin: 0; padding: 0; }

          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0d0d1a;
            color: #e0e0e0;
            min-height: 100vh;
          }

          #app {
            display: flex;
            flex-direction: column;
            height: 100vh;
          }

          #main {
            flex: 1;
            display: flex;
            padding: 20px;
            gap: 20px;
            overflow: hidden;
          }

          #status-panel h1 {
            font-size: 1.2em;
            color: #fff;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 1px solid #2a2a4e;
          }

          #battle-info {
            margin-top: auto;
            padding-top: 15px;
            border-top: 1px solid #2a2a4e;
            font-family: monospace;
            display: flex;
            flex-direction: column;
            gap: 8px;
          }

          #arena-container {
            display: flex;
            justify-content: flex-start;
            align-items: center;
          }

          #arena-canvas {
            border: 2px solid #4a4a6e;
            border-radius: 4px;
          }

          #status-panel {
            flex: 1;
            min-width: 200px;
            max-width: 400px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
          }

          .rubot-stat {
            background: #1a1a2e;
            border-radius: 8px;
            padding: 12px;
            margin-bottom: 12px;
          }

          .rubot-stat.dead {
            opacity: 0.5;
          }

          .rubot-header {
            border-left: 4px solid;
            padding-left: 8px;
            margin-bottom: 10px;
          }

          .rubot-name {
            font-weight: bold;
            font-size: 1.1em;
          }

          .rubot-size {
            color: #888;
            font-size: 0.9em;
          }

          .stat-row {
            display: flex;
            align-items: center;
            margin: 6px 0;
            font-size: 0.9em;
          }

          .stat-label {
            width: 70px;
            color: #888;
          }

          .stat-value {
            width: 80px;
            font-family: monospace;
          }

          .stat-bar {
            flex: 1;
            height: 8px;
            background: #333;
            border-radius: 4px;
            overflow: hidden;
          }

          .stat-fill {
            height: 100%;
            transition: width 0.1s;
          }

          .stat-fill.health {
            background: #4CAF50;
          }

          .stat-fill.health.medium {
            background: #FFC107;
          }

          .stat-fill.health.low {
            background: #F44336;
          }

          .stat-fill.energy {
            background: #2196F3;
          }

          #controls {
            padding: 15px 20px;
            background: #1a1a2e;
            border-top: 1px solid #2a2a4e;
            display: flex;
            align-items: center;
            gap: 10px;
          }

          #controls button {
            padding: 8px 16px;
            background: #2a2a4e;
            color: #fff;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
          }

          #controls button:hover {
            background: #3a3a5e;
          }

          #scrubber {
            flex: 1;
            margin: 0 15px;
          }

          #speed-select {
            padding: 6px;
            background: #2a2a4e;
            color: #fff;
            border: 1px solid #4a4a6e;
            border-radius: 4px;
          }

          .winner { color: #4CAF50; font-weight: bold; }
          .draw { color: #FFC107; font-weight: bold; }
        CSS
      end

      def javascript_player
        <<~JS
          class BattlePlayer {
            constructor(metadata, frames) {
              this.metadata = metadata;
              this.frames = frames.filter(f => f.type !== "summary");
              this.summary = frames.find(f => f.type === "summary");

              this.canvas = document.getElementById("arena-canvas");
              this.ctx = this.canvas.getContext("2d");

              this.currentFrame = 0;
              this.isPlaying = false;
              this.playbackSpeed = 1.0;
              this.chrononDuration = 1000 / 15;

              this.interpolationProgress = 0;
              this.lastTimestamp = null;

              this.setupCanvas();
              this.setupControls();
              this.setupColors();
              this.render();
            }

            setupCanvas() {
              const { width, height } = this.metadata.arena;
              // Leave room for controls and status panel (min 200px + padding)
              const availableWidth = window.innerWidth - 260;
              const availableHeight = window.innerHeight - 100; // controls + padding

              // Scale to fill available space
              const scaleX = availableWidth / width;
              const scaleY = availableHeight / height;
              const scale = Math.min(scaleX, scaleY);

              this.canvas.width = width * scale;
              this.canvas.height = height * scale;
              this.scale = scale;
            }

            setupColors() {
              this.rubotColors = [
                { body: "#4CAF50", dark: "#2E7D32" },
                { body: "#2196F3", dark: "#1565C0" },
                { body: "#FF9800", dark: "#EF6C00" },
                { body: "#9C27B0", dark: "#6A1B9A" }
              ];
            }

            lerp(a, b, t) {
              return a + (b - a) * t;
            }

            lerpAngle(a, b, t) {
              let diff = b - a;
              if (diff > 180) diff -= 360;
              if (diff < -180) diff += 360;
              return a + diff * t;
            }

            getInterpolatedState() {
              if (this.currentFrame >= this.frames.length - 1) {
                return this.frames[this.frames.length - 1];
              }

              const current = this.frames[this.currentFrame];
              const next = this.frames[this.currentFrame + 1];
              const t = this.interpolationProgress;

              return {
                chronon: current.chronon,
                rubots: current.rubots.map((rubot, i) => ({
                  ...rubot,
                  x: this.lerp(rubot.x, next.rubots[i].x, t),
                  y: this.lerp(rubot.y, next.rubots[i].y, t),
                  turret_angle: this.lerpAngle(rubot.turret_angle, next.rubots[i].turret_angle, t)
                })),
                bullets: current.bullets.map(bullet => ({
                  x: bullet.x + bullet.velocity_x * t,
                  y: bullet.y + bullet.velocity_y * t
                })),
                energons: current.energons
              };
            }

            animate(timestamp) {
              if (!this.isPlaying) return;

              if (this.lastTimestamp === null) {
                this.lastTimestamp = timestamp;
              }

              const delta = timestamp - this.lastTimestamp;
              const frameAdvance = (delta / this.chrononDuration) * this.playbackSpeed;

              this.interpolationProgress += frameAdvance;

              while (this.interpolationProgress >= 1.0 && this.currentFrame < this.frames.length - 1) {
                this.interpolationProgress -= 1.0;
                this.currentFrame++;
                this.updateScrubber();
              }

              if (this.currentFrame >= this.frames.length - 1) {
                this.interpolationProgress = 0;
                this.isPlaying = false;
                this.updatePlayButton();
                this.showSummary();
              }

              this.render();
              this.lastTimestamp = timestamp;

              if (this.isPlaying) {
                requestAnimationFrame((ts) => this.animate(ts));
              }
            }

            render() {
              const state = this.getInterpolatedState();

              this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

              this.drawArena();
              this.drawEnergons(state.energons);
              this.drawBullets(state.bullets);
              this.drawRubots(state.rubots);

              this.updateStatusPanel(state);
              this.updateChrononDisplay(state.chronon);
            }

            drawArena() {
              const ctx = this.ctx;

              ctx.fillStyle = "#1a1a2e";
              ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

              ctx.strokeStyle = "#2a2a4e";
              ctx.lineWidth = 1;
              const gridSize = 25 * this.scale;

              for (let x = 0; x < this.canvas.width; x += gridSize) {
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, this.canvas.height);
                ctx.stroke();
              }

              for (let y = 0; y < this.canvas.height; y += gridSize) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(this.canvas.width, y);
                ctx.stroke();
              }

              ctx.strokeStyle = "#4a4a6e";
              ctx.lineWidth = 3;
              ctx.strokeRect(0, 0, this.canvas.width, this.canvas.height);
            }

            drawRubot(rubot, index) {
              const ctx = this.ctx;
              const x = rubot.x * this.scale;
              const y = this.canvas.height - (rubot.y * this.scale);
              const radius = rubot.radius * this.scale;
              const colors = this.rubotColors[index % this.rubotColors.length];

              if (!rubot.alive) {
                ctx.globalAlpha = 0.3;
              }

              if (rubot.shield_level > 0) {
                const shieldRadius = radius + 2 * this.scale;
                const shieldAlpha = Math.min(rubot.shield_level / 40, 0.85);
                ctx.beginPath();
                ctx.arc(x, y, shieldRadius, 0, Math.PI * 2);
                ctx.fillStyle = "rgba(140, 220, 255, " + shieldAlpha + ")";
                ctx.fill();
              }

              ctx.beginPath();
              ctx.arc(x, y, radius, 0, Math.PI * 2);
              ctx.fillStyle = colors.body;
              ctx.fill();
              ctx.strokeStyle = colors.dark;
              // Border thickness based on size
              ctx.lineWidth = rubot.size === "small" ? 1 : rubot.size === "large" ? 4 : 2;
              ctx.stroke();

              const turretAngle = -rubot.turret_angle * Math.PI / 180;
              const turretLength = radius * 1.4;
              const turretWidth = radius * 0.3;

              ctx.save();
              ctx.translate(x, y);
              ctx.rotate(turretAngle);

              ctx.fillStyle = colors.dark;
              ctx.fillRect(0, -turretWidth/2, turretLength, turretWidth);

              ctx.restore();

              const healthBarWidth = radius * 2;
              const healthBarHeight = 4 * this.scale;
              const healthPercent = rubot.health / rubot.max_health;

              ctx.fillStyle = "#333";
              ctx.fillRect(x - healthBarWidth/2, y - radius - 10 * this.scale, healthBarWidth, healthBarHeight);

              const healthColor = healthPercent > 0.6 ? "#4CAF50" :
                                  healthPercent > 0.3 ? "#FFC107" : "#F44336";
              ctx.fillStyle = healthColor;
              ctx.fillRect(x - healthBarWidth/2, y - radius - 10 * this.scale,
                           healthBarWidth * healthPercent, healthBarHeight);

              ctx.globalAlpha = 1.0;
            }

            drawRubots(rubots) {
              rubots.forEach((rubot, i) => this.drawRubot(rubot, i));
            }

            drawBullets(bullets) {
              const ctx = this.ctx;
              const bulletRadius = 3 * this.scale;

              ctx.fillStyle = "#FFEB3B";
              ctx.shadowColor = "#FFEB3B";
              ctx.shadowBlur = 5;

              bullets.forEach(bullet => {
                const x = bullet.x * this.scale;
                const y = this.canvas.height - (bullet.y * this.scale);

                ctx.beginPath();
                ctx.arc(x, y, bulletRadius, 0, Math.PI * 2);
                ctx.fill();
              });

              ctx.shadowBlur = 0;
            }

            drawEnergons(energons) {
              const ctx = this.ctx;
              const energonRadius = 4 * this.scale;
              const diamondRadius = energonRadius * 0.6;

              energons.forEach(energon => {
                const x = energon.x * this.scale;
                const y = this.canvas.height - (energon.y * this.scale);

                const gradient = ctx.createRadialGradient(x, y, 0, x, y, energonRadius * 2);
                gradient.addColorStop(0, "rgba(0, 255, 150, 0.8)");
                gradient.addColorStop(1, "rgba(0, 255, 150, 0)");
                ctx.fillStyle = gradient;
                ctx.fillRect(x - energonRadius * 2, y - energonRadius * 2,
                             energonRadius * 4, energonRadius * 4);

                ctx.beginPath();
                ctx.moveTo(x, y - diamondRadius);
                ctx.lineTo(x + diamondRadius, y);
                ctx.lineTo(x, y + diamondRadius);
                ctx.lineTo(x - diamondRadius, y);
                ctx.closePath();
                ctx.fillStyle = "#00FF96";
                ctx.fill();
                ctx.strokeStyle = "#00CC78";
                ctx.lineWidth = 2;
                ctx.stroke();
              });
            }

            updateStatusPanel(state) {
              const container = document.getElementById("rubot-stats");
              container.innerHTML = state.rubots.map((rubot, i) => {
                const colors = this.rubotColors[i % this.rubotColors.length];
                const healthPercent = (rubot.health / rubot.max_health) * 100;
                const healthClass = healthPercent > 60 ? "" : healthPercent > 30 ? "medium" : "low";
                return '<div class="rubot-stat ' + (rubot.alive ? '' : 'dead') + '">' +
                  '<div class="rubot-header" style="border-color: ' + colors.body + '">' +
                    '<span class="rubot-name">' + rubot.name + '</span> ' +
                    '<span class="rubot-size">(' + rubot.size + ')</span>' +
                  '</div>' +
                  '<div class="stat-row">' +
                    '<span class="stat-label">Health:</span>' +
                    '<span class="stat-value">' + rubot.health + '/' + rubot.max_health + '</span>' +
                    '<div class="stat-bar"><div class="stat-fill health ' + healthClass + '" style="width: ' + healthPercent + '%"></div></div>' +
                  '</div>' +
                  '<div class="stat-row">' +
                    '<span class="stat-label">Energy:</span>' +
                    '<span class="stat-value">' + rubot.energy + '/100</span>' +
                    '<div class="stat-bar"><div class="stat-fill energy" style="width: ' + rubot.energy + '%"></div></div>' +
                  '</div>' +
                  '<div class="stat-row">' +
                    '<span class="stat-label">Shield:</span>' +
                    '<span class="stat-value">' + rubot.shield_level + '</span>' +
                  '</div>' +
                '</div>';
              }).join("");
            }

            setupControls() {
              document.getElementById("btn-play-pause").onclick = () => this.togglePlay();
              document.getElementById("btn-start").onclick = () => this.goToStart();
              document.getElementById("btn-end").onclick = () => this.goToEnd();
              document.getElementById("btn-prev").onclick = () => this.stepBack();
              document.getElementById("btn-next").onclick = () => this.stepForward();

              const scrubber = document.getElementById("scrubber");
              scrubber.max = this.frames.length - 1;
              scrubber.oninput = () => {
                this.currentFrame = parseInt(scrubber.value);
                this.interpolationProgress = 0;
                this.render();
              };

              document.getElementById("speed-select").onchange = (e) => {
                this.playbackSpeed = parseFloat(e.target.value);
              };

              document.addEventListener("keydown", (e) => {
                if (e.code === "Space") { e.preventDefault(); this.togglePlay(); }
                if (e.code === "ArrowLeft") this.stepBack();
                if (e.code === "ArrowRight") this.stepForward();
                if (e.code === "Home") this.goToStart();
                if (e.code === "End") this.goToEnd();
              });
            }

            togglePlay() {
              this.isPlaying = !this.isPlaying;
              this.updatePlayButton();

              if (this.isPlaying) {
                this.lastTimestamp = null;
                requestAnimationFrame((ts) => this.animate(ts));
              }
            }

            updatePlayButton() {
              document.getElementById("btn-play-pause").textContent =
                this.isPlaying ? "Pause ⏸" : "Play ▶";
            }

            updateScrubber() {
              document.getElementById("scrubber").value = this.currentFrame;
            }

            updateChrononDisplay(chronon) {
              document.getElementById("chronon-display").textContent =
                "Chronon: " + chronon + " / " + this.frames.length;
            }

            goToStart() {
              this.currentFrame = 0;
              this.interpolationProgress = 0;
              this.updateScrubber();
              this.render();
            }

            goToEnd() {
              this.currentFrame = this.frames.length - 1;
              this.interpolationProgress = 0;
              this.isPlaying = false;
              this.updatePlayButton();
              this.updateScrubber();
              this.render();
              this.showSummary();
            }

            stepForward() {
              if (this.currentFrame < this.frames.length - 1) {
                this.currentFrame++;
                this.interpolationProgress = 0;
                this.updateScrubber();
                this.render();
              }
            }

            stepBack() {
              if (this.currentFrame > 0) {
                this.currentFrame--;
                this.interpolationProgress = 0;
                this.updateScrubber();
                this.render();
              }
            }

            showSummary() {
              if (this.summary) {
                const display = document.getElementById("winner-display");
                if (this.summary.winner) {
                  display.textContent = "Winner: " + this.summary.winner.name;
                  display.classList.add("winner");
                } else {
                  display.textContent = "Draw";
                  display.classList.add("draw");
                }
              }
            }
          }

          document.addEventListener("DOMContentLoaded", () => {
            new BattlePlayer(METADATA, FRAMES);
          });
        JS
      end
    end
  end
end
