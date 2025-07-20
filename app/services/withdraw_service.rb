# frozen_string_literal: true

class WithdrawService
  include Idempotent

  def initialize(user:, amount_cents:, idempotency_key:)
    @user = user
    @amount_cents = amount_cents
    @idempotency_key = idempotency_key
  end

  def call
    validate_amount!

    with_idempotency(@idempotency_key) do
      perform_withdrawal
    end
  end

  private

  def validate_amount!
    raise ArgumentError, 'Amount must be positive' unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
  end

  def perform_withdrawal
    wallet = @user.wallet

    begin
      transaction = Transaction.create!(
        wallet: wallet,
        transaction_type: 'withdrawal',
        amount_cents: @amount_cents,
        currency: wallet.currency,
        idempotency_key: @idempotency_key,
        status: 'pending'
      )
    rescue StandardError => e
      return ServiceResult.new(success: false, error: e.message)
    end

    begin
      ActiveRecord::Base.transaction do
        wallet.lock!
        wallet.withdraw!(@amount_cents)
      end

      transaction.update!(status: 'completed')
      ServiceResult.new(success: true, data: transaction)
    rescue StandardError => e
      transaction.update!(
        status: 'failed',
        failed_reason: e.message
      )
      ServiceResult.new(success: false, error: e.message)
    end
  end
end
