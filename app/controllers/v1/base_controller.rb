# frozen_string_literal: true

# app/controllers/v1/base_controller.rb

module V1
  class BaseController < ApplicationController
    before_action :authenticate_user!

    private

    # ThinkingProcess: Simplified user authentication, for its not the focus of this project,
    # for production, we could use more robust and secure authentication, like JWT, OAuth, etc.
    def authenticate_user!
      api_key = request.headers['X-User-API-Key']
      @current_user = User.find_by(api_key: api_key)

      render json: { error: 'Unauthorized' }, status: :unauthorized unless @current_user
    end

    def handle_service_call(service)
      result = service.call

      if result.success?
        render json: result.data, status: :created
      else
        render json: { error: result.error }, status: :unprocessable_entity
      end
    rescue Idempotent::AlreadyProcessingError
      render json: { error: 'Request is already being processed' }, status: :conflict
    rescue ArgumentError => e
      render json: { error: e.message }, status: :bad_request
    end

    attr_reader :current_user
  end
end
