module Storytelling
  class OfflineProvider
    MESSAGE = "В данный момент нейросеть не подключена. Продолжение истории появится после подключения ИИ. Пока можно изучить интерфейс и настроить музыку.".freeze

    def name
      "offline"
    end

    def model_identifier
      "demo"
    end

    def call(payload:)
      { "narration" => MESSAGE, "summary" => payload["summary"].presence || "Демонстрационное прохождение: нейросеть пока не подключена." }
    end
  end
end
