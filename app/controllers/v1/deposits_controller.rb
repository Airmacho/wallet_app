# frozen_string_literal: true

module V1
  class DepositsController < V1::BaseController
    include IdempotencyHandler
    before_action :require_idempotency_key, only: [:create]

    def create
      service = DepositService.new(
        user: current_user,
        amount_cents: deposit_params[:amount_cents],
        idempotency_key: request.headers['Idempotency-Key']
      )

      handle_service_call(service)
    end

    private

    def deposit_params
      params.require(:deposit).permit(:amount_cents)
    end
  end
end
