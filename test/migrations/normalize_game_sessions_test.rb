require "test_helper"
require "open3"
require "tmpdir"

class NormalizeGameSessionsTest < ActiveSupport::TestCase
  test "legacy data survives normalization and failed imports roll back" do
    Dir.mktmpdir("rpi-legacy-") do |directory|
      database = File.join(directory, "legacy.sqlite3").tr("\\", "/")
      stdout, stderr, status = Open3.capture3(
        { "DATABASE_URL" => "sqlite3:#{database}", "RAILS_ENV" => "test" },
        RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner",
        Rails.root.join("test/support/legacy_migration_check.rb").to_s
      )
      assert status.success?, "Migration subprocess failed:\n#{stdout}\n#{stderr}"
      assert_includes stdout, "LEGACY_MIGRATION_OK"
    end
  end
end
