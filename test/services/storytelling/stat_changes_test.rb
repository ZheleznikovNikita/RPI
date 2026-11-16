require "test_helper"

class Storytelling::StatChangesTest < ActiveSupport::TestCase
  test "accepts integer boundaries and preserves old responses without changes" do
    assert_equal({ "health_delta" => 0, "stamina_delta" => 0 }, Storytelling::StatChanges.parse({}))
    [ [ -30, -40 ], [ 0, 0 ], [ 20, 30 ] ].each do |health, stamina|
      changes = { "health_delta" => health, "stamina_delta" => stamina }
      assert_equal changes, Storytelling::StatChanges.parse(changes, required: true)
    end
    assert_raises(ArgumentError) { Storytelling::StatChanges.parse({}, required: true) }
  end

  test "rejects partial strings floats booleans null and excessive changes" do
    { "health_delta" => [ -31, 21, "-5", 0.5, nil, true ],
      "stamina_delta" => [ -41, 31, "0", 1.0, nil, false ] }.each do |key, invalid|
      invalid.each do |value|
        response = { "health_delta" => 0, "stamina_delta" => 0 }.merge(key => value)
        assert_raises(ArgumentError) { Storytelling::StatChanges.parse(response) }
      end
      assert_raises(ArgumentError) { Storytelling::StatChanges.parse({ key => 0 }) }
    end
  end
end
