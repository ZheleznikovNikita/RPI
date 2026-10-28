Rails.application.routes.draw do
  root "home#index"

  get "game", to: "game#show"
  post "game", to: "game#command"
  get "game/new", to: "game#new", as: :new_game
  post "game/start", to: "game#start", as: :start_game
  post "game/finish", to: "game#finish", as: :finish_game
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
  get "ui-kit", to: "ui_kit#show", as: :ui_kit
  get "register", to: "registrations#new", as: :register
  post "register", to: "registrations#create"
  get "profile", to: "profiles#show", as: :profile
  patch "profile", to: "profiles#update"
  get "statistics", to: "statistics#index", as: :statistics
  get "settings", to: "settings#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
