# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rubowar"

require "minitest/autorun"

# Note: No global event bus cleanup needed anymore.
# EventBus is now instantiated per-battle, so each test gets its own isolated instance.
