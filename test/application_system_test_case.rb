require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include ActiveJob::TestHelper
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]

  setup do
    ActionCable.server.config.cable = { "adapter" => "async" }
    clear_enqueued_jobs
    # Keep typewriter animation out of timing assertions; its preference UI is separate.
    Capybara.default_max_wait_time = 5
  end
end
