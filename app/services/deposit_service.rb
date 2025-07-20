# frozen_string_literal: true

class DepositService
  include Idempotent

  def initialize(user:, amount_cents:, idempotency_key:)
    @user = user
    @amount_cents = amount_cents
    @idempotency_key = idempotency_key
  end

  def call
    validate_amount!

    with_idempotency(@idempotency_key) do
      perform_deposit
    end
  end

  private

  def validate_amount!
    raise ArgumentError, 'Amount must be positive' unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
  end

  def perform_deposit
    wallet = @user.wallet

    # ThinkingProcess: This ensures failed transactions are recorded even when business logic fails,
    # so we can audit the failed transactions.
    begin
      transaction = Transaction.create!(
        wallet: wallet,
        transaction_type: 'deposit',
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
        # ThinkingProcess: pessimistic locking the wallet to prevent race conditions from concurrent deposits.
        wallet.lock!
        wallet.deposit!(@amount_cents)
      end

      transaction.update!(status: 'completed')
      ServiceResult.new(success: true, data: transaction)
    rescue StandardError => e
      transaction.update!(
        status: 'failed',
        metadata: { failure_reason: e.message, failed_at: Time.current }
      )
      ServiceResult.new(success: false, error: e.message)
    end
  end
end
