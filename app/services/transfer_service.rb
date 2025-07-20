# frozen_string_literal: true

class TransferService
  include Idempotent

  def initialize(from_user:, to_user:, amount_cents:, idempotency_key: nil)
    @from_user = from_user
    @to_user = to_user
    @amount_cents = amount_cents
    @idempotency_key = idempotency_key
  end

  def call
    validate_amount!
    validate_different_users!

    with_idempotency(@idempotency_key) do
      perform_transfer
    end
  end

  private

  def perform_transfer
    from_wallet = @from_user.wallet

    transfer_out_transaction = Transaction.create!(
      wallet: from_wallet,
      transaction_type: 'transfer_out',
      amount_cents: @amount_cents,
      currency: from_wallet.currency,
      status: 'pending',
      idempotency_key: @idempotency_key
    )

    begin
      ActiveRecord::Base.transaction do
        # ThinkingProcess: Lock wallets in a consistent order to prevent circular deadlocks
        wallets = [@from_user.wallet, @to_user.wallet].sort_by(&:id)
        wallets.each(&:lock!)

        # ThinkingProcess: Re-fetch wallets after locking to ensure we have the latest state
        from_wallet = @from_user.wallet.reload
        to_wallet = @to_user.wallet.reload

        converted_amount_cents = convert_currency(@amount_cents, from_wallet.currency, to_wallet.currency)

        from_wallet.withdraw!(@amount_cents)
        to_wallet.deposit!(converted_amount_cents)

        # Create transfer_in transaction
        Transaction.create!(
          wallet: to_wallet,
          transaction_type: 'transfer_in',
          amount_cents: converted_amount_cents,
          currency: to_wallet.currency,
          status: 'completed',
          idempotency_key: @idempotency_key
        )

        # Mark transfer_out as completed
        transfer_out_transaction.update!(status: 'completed')
      end

      ServiceResult.new(success: true, data: transfer_out_transaction)
    rescue StandardError => e
      # Record failure reason in metadata (consistent with deposit/withdraw)
      transfer_out_transaction.update!(
        status: 'failed',
        metadata: { failure_reason: e.message, failed_at: Time.current }
      )
      ServiceResult.new(success: false, error: e.message)
    end
  end

  def convert_currency(amount_cents, from_currency, to_currency)
    return amount_cents if from_currency == to_currency

    # ThinkingProcess: Use Money gem for currency conversion
    from_money = Money.new(amount_cents, from_currency)
    converted_money = from_money.exchange_to(to_currency)
    converted_money.cents
  rescue Money::Currency::UnknownCurrency => e
    raise ArgumentError, "Unknown currency: #{e.message}"
  rescue Money::Bank::UnknownRate => e
    raise ArgumentError, "Currency conversion rate not available for #{from_currency} to #{to_currency}: #{e.message}"
  rescue StandardError => e
    raise ArgumentError, "Currency conversion failed: #{e.message}"
  end

  def validate_amount!
    raise ArgumentError, 'Amount must be positive' unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
  end

  def validate_different_users!
    raise ArgumentError, 'Cannot transfer to self' if @from_user.id == @to_user.id
  end
end
