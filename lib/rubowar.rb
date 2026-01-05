# frozen_string_literal: true

require_relative "rubowar/version"
require_relative "rubowar/rubot_state"
require_relative "rubowar/arena_state"
require_relative "rubowar/rubot_runner"
require_relative "rubowar/rubot"
require_relative "rubowar/bullet"
require_relative "rubowar/arena"
require_relative "rubowar/battle"
require_relative "rubowar/renderers/terminal"

module Rubowar
  class Error < StandardError; end
end
