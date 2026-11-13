require "test_helper"

class GameChannelTest < ActionCable::Channel::TestCase
  test "only the authenticated users stream is used regardless of supplied user id" do
    player = create_game_user
    foreign = create_game_user
    stub_connection current_user: player
    subscribe signed_stream_name: GameChannel.signed_stream_name([ :game_ui ]), user_id: foreign.id
    assert subscription.confirmed?
    assert_has_stream "private_game_user_#{player.id}"
    assert_not_includes subscription.streams, "private_game_user_#{foreign.id}"
  end

  test "tampered and unrelated signed stream names are rejected" do
    stub_connection current_user: create_game_user
    subscribe signed_stream_name: "tampered"
    assert subscription.rejected?
    subscribe signed_stream_name: GameChannel.signed_stream_name([ "private_game_user_123" ])
    assert subscription.rejected?
  end
end
