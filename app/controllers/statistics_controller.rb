class StatisticsController < ApplicationController
  def index
    unless user_signed_in?
      redirect_to login_path(profile_navigation_options), alert: "Войдите, чтобы посмотреть статистику."
      return
    end

    @game_sessions = current_user.recent_game_sessions.to_a
    @action_counts = PlayerAction.completed.where(game_session_id: @game_sessions.map(&:id)).group(:game_session_id).count
  end
end
