require "test_helper"

class ConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "authenticated session connects and anonymous or deleted account is rejected" do
    player = create_game_user
    connect session: { user_id: player.id }
    assert_equal player, connection.current_user
    disconnect
    assert_reject_connection { connect }
    id = player.id
    player.destroy!
    assert_reject_connection { connect session: { user_id: id } }
  end
end
