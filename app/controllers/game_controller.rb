class GameController < ApplicationController
  SCENE_INTRO = "Дорога тонет в тёплом тумане. Впереди — старые ворота. Как вы поступите?".freeze

  def show
    @game_session = current_user&.active_game_session
    @story_actions = @game_session ? @game_session.player_actions.completed.includes(:story_turns).to_a : []
    @inventory_items = @game_session ? @game_session.inventory.inventory_items.order(:name).to_a : []
  end

  def new
    if user_signed_in?
      @game_session = current_user.active_game_session
    else
      redirect_to game_path
    end
  end

  def start
    unless user_signed_in?
      redirect_to game_path
      return
    end

    current_user.with_lock do
      active = current_user.reload.active_game_session
      if active && params[:replace_game_session_id].to_s != active.id.to_s
        redirect_to new_game_path, alert: "Подтвердите замену текущего прохождения."
        return
      end
      current_user.start_game_session!(title: "У старых ворот")
    end

    redirect_to game_path, status: :see_other
  rescue ActiveRecord::StatementTimeout, ActiveRecord::RecordNotUnique
    redirect_to root_path, alert: "Прохождение сейчас обновляется. Попробуйте ещё раз."
  end

  def finish
    game = current_user&.active_game_session
    unless game
      redirect_to game_path, alert: "Нет активного прохождения для завершения."
      return
    end

    if params[:game_session_id].present? && params[:game_session_id].to_s != game.id.to_s
      redirect_to game_path, alert: "Прохождение изменилось. Обновите страницу перед завершением."
      return
    end

    game.finish!
    redirect_to statistics_path(from: "finished_game"), notice: "Прохождение завершено. Результат сохранён.", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::StatementTimeout
    redirect_to game_path, alert: "Сначала дождитесь завершения текущего действия."
  end

  def command
    command = params[:command]
    unless command.is_a?(String) && command.strip.present? && command.length <= 2_000
      respond_to_command(status: "invalid", text: "Введите действие длиной от 1 до 2000 символов.", http_status: :unprocessable_entity)
      return
    end

    game = current_user&.active_game_session
    if params[:game_session_id].present? && params[:game_session_id].to_s != game&.id.to_s
      respond_to_command(status: "conflict", text: "Прохождение изменилось. Обновите страницу перед отправкой.", http_status: :conflict)
      return
    end

    if current_user && !game
      current_user.with_lock do
        game = current_user.reload.active_game_session || current_user.start_game_session!(title: "У старых ворот")
      end
    end

    result = Storytelling::Narrator.new.call(command: command.strip, game_session: game)
    respond_to_command(status: result.status, text: result.text, http_status: result.status == "error" ? :bad_gateway : :ok, game: game)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotFound, ActiveRecord::StatementTimeout
    respond_to_command(status: "conflict", text: "Действие ещё обрабатывается или прохождение изменилось. Обновите страницу и попробуйте снова.", http_status: :conflict)
  end

  private

  def respond_to_command(status:, text:, http_status:, game: nil)
    respond_to do |format|
      format.json { render json: { status: status, text: text, game_session_id: game&.id }, status: http_status }
      format.html do
        flash[:story_feedback] = text unless status == "completed" && game
        flash[:story_feedback_status] = status
        flash[:animate_story] = status == "completed"
        redirect_to game_path, status: :see_other
      end
    end
  end
end
