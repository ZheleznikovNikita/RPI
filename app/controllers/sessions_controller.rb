class SessionsController < ApplicationController
  def new
    @email = params[:email]
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      redirect_to profile_path, notice: "Вы вошли как #{user.name}."
    else
      @email = params[:email]
      flash.now[:alert] = "Не удалось войти: проверьте email и пароль."
      render :new, status: :unprocessable_entity
    end
  end
end