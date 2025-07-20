# frozen_string_literal: true

module IdempotencyHandler
  extend ActiveSupport::Concern

  # Setup the error handlers at the class level
  included do
    rescue_from Idempotent::AlreadyProcessingError, with: :request_in_progress
    rescue_from ArgumentError, with: :bad_request
  end

  private

  def require_idempotency_key
    return if request.headers['Idempotency-Key'].present?

    render json: { error: 'Idempotency-Key header is missing' }, status: :bad_request
  end

  def request_in_progress(exception)
    render json: { error: exception.message }, status: :conflict
  end

  def bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end
end
