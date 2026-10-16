class ApplicationController < ActionController::Base
  helper_method :current_user, :user_signed_in?, :profile_navigation_options

  private

  def profile_navigation_options
    params[:from] == "game" ? { from: "game" } : {}
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def user_signed_in?
    current_user.present?
  end
end
