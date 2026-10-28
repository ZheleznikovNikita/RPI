require "test_helper"

class StatisticsTest < ActionDispatch::IntegrationTest
  setup { @user = create_game_user }

  def sign_in
    post login_path, params: { email: @user.email, password: "Lantern!Orbit7Cedar" }
  end

  test "statistics requires authentication and keeps navigation context" do
    get statistics_path(from: "game")
    assert_redirected_to login_path(from: "game")
  end

  test "empty statistics returns to profile without breaking return to game" do
    sign_in
    get profile_path(from: "game")
    assert_select ".profile-card-header form[data-confirm-logout] button[aria-label='Выйти из аккаунта']"
    assert_select ".profile-statistics a[href=?]", statistics_path(from: "game"), text: "Статистика"
    get statistics_path(from: "game")
    assert_response :success
    assert_select "h1", "Статистика"
    assert_select ".statistics-empty h2", "Завершённых прохождений пока нет"
    assert_select ".statistics-row", count: 0
    assert_select ".back-arrow[href=?]", profile_path(from: "game")
  end

  test "statistics opened after finishing returns to menu while profile visits retain their context" do
    sign_in
    get statistics_path(from: "finished_game")
    assert_select ".back-arrow[href=?][aria-label='В главное меню']", root_path
    get statistics_path
    assert_select ".back-arrow[href=?][aria-label='Назад в профиль']", profile_path
    get statistics_path(from: "game")
    assert_select ".back-arrow[href=?]", profile_path(from: "game")
  end

  test "list shows at most ten completed games of the signed in user" do
    finished = 11.times.map do |index|
      game = @user.start_game_session!(title: "Прохождение #{index}")
      game.finish!
      game.update!(completed_at: Time.utc(2026, 10, 1) + index.days)
      game
    end
    @user.start_game_session!(title: "Ещё не закончено")
    foreign = create_game_user.start_game_session!(title: "Чужое прохождение").finish!
    sign_in
    get statistics_path, params: { user_id: foreign.user_id }
    assert_response :success
    assert_select ".statistics-row", count: 10
    assert_select ".statistics-game h2" do |titles|
      assert_equal finished.reverse.first(10).map(&:title), titles.map(&:text)
    end
    assert_select ".statistics-game h2", text: "Чужое прохождение", count: 0
    assert_select ".statistics-game h2", text: "Ещё не закончено", count: 0
  end

  test "results show completed actions and final stats without inventing a win or loss" do
    game = @user.start_game_session!(title: "У старых ворот")
    complete_action(game)
    game.submit_action!(command: "Отменённое действие").cancel!
    game.update!(health: 74, stamina: 28)
    game.finish!
    game.update!(completed_at: Time.utc(2026, 10, 23, 12, 0))
    sign_in
    get statistics_path
    assert_select ".statistics-metrics dd" do |values|
      assert_equal [ "1", "74 / 100", "28 / 100" ], values.map { |value| value.text.strip }
    end
    assert_select "time[datetime=?]", game.completed_at.iso8601, text: "23.10.2026, 15:00 МСК"
  end
end
