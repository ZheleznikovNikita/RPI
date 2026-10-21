ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/game_model_helpers"

module ActiveSupport
  class TestCase
    include GameModelHelpers

    # SQLite tests share a database; serialize writes rather than racing transactions.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
