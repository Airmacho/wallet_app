# frozen_string_literal: true

module V1
  class TransfersController < V1::BaseController
    include IdempotencyHandler
    before_action :require_idempotency_key, only: [:create]

    def create
      to_user = find_recipient_user
      return unless to_user

      service = TransferService.new(
        from_user: current_user,
        to_user: to_user,
        amount_cents: transfer_params[:amount_cents],
        idempotency_key: request.headers['Idempotency-Key']
      )

      handle_service_call(service)
    end

    private

    def find_recipient_user
      to_user = User.find_by(email: transfer_params[:to_email])

      unless to_user
        render json: { error: 'Recipient user not found' }, status: :not_found
        return nil
      end

      to_user
    end

    def transfer_params
      params.require(:transfer).permit(:to_email, :amount_cents)
    end
  end
end
