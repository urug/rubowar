# frozen_string_literal: true

require "test_helper"

describe Rubowar do
  it "has a version number" do
    _(Rubowar::VERSION).wont_be_nil
  end
end
