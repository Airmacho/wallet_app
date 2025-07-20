# frozen_string_literal: true

# app/controllers/v1/me_controller.rb

module V1
  class MeController < V1::BaseController
    # GET /v1/me/wallet
    # response example:
    # {
    #   "id": 1,
    #   "balance_cents": 10000,
    #   "currency": "USD"
    # }
    def wallet
      wallet = current_user.wallet
      render json: wallet
    end

    # GET /v1/me/transactions
    # response example:
    # [
    #   {
    #     "id": 1,
    #     "transaction_type": "deposit",
    #     "amount_cents": 10000,
    #     "currency": "USD",
    #     "status": "completed",
    #     "failed_reason": "Insufficient funds",
    #     "created_at": "2021-01-01T00:00:00Z"
    #   }
    # ]
    def transactions
      wallet = current_user.wallet
      transactions = wallet.transactions.order(created_at: :desc)
      render json: transactions
    end
  end
end
