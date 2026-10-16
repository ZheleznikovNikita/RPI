require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "menu pages use an arrow back to main menu" do
    [ settings_path, register_path, login_path, profile_path ].each do |path|
      get path
      assert_response :success
      assert_select ".back-arrow[href=?][aria-label='В главное меню'][title='В главное меню']", root_path
    end
  end

  test "game profile and ui kit retain return route" do
    get game_path
    assert_select ".hud-right a[href=?]", profile_path(from: "game")
    assert_select ".hud-right a:last-child[href=?]", root_path
    get profile_path(from: "game")
    assert_select ".back-arrow[href=?][aria-label='Назад в игру']", game_path
    assert_select "a[href=?]", login_path(from: "game")
    assert_select "a[href=?]", register_path(from: "game")
    assert_select ".ui-kit-link[href=?]", ui_kit_path(from: "game")
    get ui_kit_path(from: "game")
    assert_select ".back-arrow[href=?][aria-label='Назад в профиль']", profile_path(from: "game")
    get profile_path(from: "game")
    assert_select ".back-arrow[href=?]", game_path
  end

  test "authentication forms preserve game origin" do
    get login_path(from: "game")
    assert_select "form[action=?]", login_path(from: "game")
    assert_select "a[href=?]", register_path(from: "game")
    get register_path(from: "game")
    assert_select "form[action=?]", register_path(from: "game")
    post register_path(from: "game"), params: { user: { name: "Игрок", email: "navigation@example.test", password: "Cedar!Orbit9Lantern", password_confirmation: "Cedar!Orbit9Lantern" } }
    assert_redirected_to profile_path(from: "game")
    follow_redirect!
    assert_select ".back-arrow[href=?]", game_path
  end

  test "direct ui kit returns to profile and unknown origins fall back to menu" do
    get ui_kit_path
    assert_select ".back-arrow[href=?]", profile_path
    get profile_path(from: "https://example.com")
    assert_select ".back-arrow[href=?]", root_path
    assert_select ".ui-kit-link[href=?]", ui_kit_path
  end
end
