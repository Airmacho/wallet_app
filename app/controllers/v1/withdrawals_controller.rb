# frozen_string_literal: true

module V1
  class WithdrawalsController < V1::BaseController
    include IdempotencyHandler
    before_action :require_idempotency_key, only: [:create]

    def create
      service = WithdrawService.new(
        user: current_user,
        amount_cents: withdrawal_params[:amount_cents],
        idempotency_key: request.headers['Idempotency-Key']
      )

      handle_service_call(service)
    end

    private

    def withdrawal_params
      params.require(:withdrawal).permit(:amount_cents)
    end
  end
end
