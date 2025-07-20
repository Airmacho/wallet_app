# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check endpoint
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Wallet API v1
  namespace :v1 do
    # RESTful route for creating a deposit
    resources :deposits, only: [:create]

    # RESTful route for creating a withdrawal
    resources :withdrawals, only: [:create]

    # RESTful route for creating a transfer
    resources :transfers, only: [:create]

    # Current user resources
    namespace :me do
      get :wallet
      get :transactions
    end
  end
end
