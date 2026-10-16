class ProfilesController < ApplicationController
  before_action :set_profile_user

  def show
    @user = current_user || User.new
  end

  def update
    unless user_signed_in?
      redirect_to profile_path(profile_navigation_options), alert: "Чтобы изменить имя, зарегистрируйтесь или войдите в систему."
      return
    end

    if @user.update(user_params)
      redirect_to profile_path(profile_navigation_options), notice: "Имя пользователя успешно обновлено."
    else
      flash.now[:alert] = "Не удалось обновить имя."
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_profile_user
    @user = current_user
  end

  def user_params
    params.require(:user).permit(:name)
  end
end
