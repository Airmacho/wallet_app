# frozen_string_literal: true

module Idempotent
  extend ActiveSupport::Concern

  class AlreadyProcessingError < StandardError; end

  IDEMPOTENCY_KEY_PREFIX = 'idempotency_key:'

  IN_PROGRESS_MARKER = 'IN_PROGRESS'

  # TTL for the in-progress marker to prevent permanent locks.
  IN_PROGRESS_TTL = 1.minute
  # TTL for the cached result of a successful operation.
  RESULT_TTL = 1.hour

  # ThinkingProcess: The controller layer only ensures the presence of the idempotency key.
  # The actual validation of idempotency is handled in the service layer.
  # This allows the idempotency logic to be reused in other non-controller contexts,
  # like background jobs, test cases, etc.
  def with_idempotency(key, &)
    validate_idempotency_key(key)

    existing_transaction = find_transaction_by_key(key)
    return build_result_from_transaction(existing_transaction) if existing_transaction

    redis_key = build_redis_key(key)
    handle_redis_idempotency(redis_key, &)
  end

  private

  def validate_idempotency_key(key)
    raise ArgumentError, 'An idempotency key must be provided for this operation.' if key.blank?
  end

  def build_redis_key(key)
    "#{IDEMPOTENCY_KEY_PREFIX}#{key}"
  end

  def handle_redis_idempotency(redis_key, &)
    set_result = REDIS_CLIENT.set(redis_key, IN_PROGRESS_MARKER, nx: true, ex: IN_PROGRESS_TTL)

    if set_result
      execute_with_cleanup(redis_key, &)
    else
      handle_existing_redis_key(redis_key)
    end
  end

  def execute_with_cleanup(redis_key)
    result = yield
    REDIS_CLIENT.set(redis_key, result.to_json, ex: RESULT_TTL)
    result
  rescue StandardError => e
    REDIS_CLIENT.del(redis_key)
    raise e
  end

  def handle_existing_redis_key(redis_key)
    existing_value = REDIS_CLIENT.get(redis_key)

    if existing_value == IN_PROGRESS_MARKER
      raise AlreadyProcessingError, 'Request with idempotency key is being processed.'
    end

    parse_cached_result(existing_value)
  end

  def parse_cached_result(existing_value)
    cached_data = JSON.parse(existing_value, symbolize_names: true)
    ServiceResult.new(success: true, data: cached_data[:data], error: cached_data[:error])
  rescue StandardError
    ServiceResult.new(success: false, error: 'Failed to parse cached result')
  end

  def find_transaction_by_key(key)
    transactions = Transaction.where(idempotency_key: key)
    return nil if transactions.empty?

    # ThinkingProcess: For transfer operations, prioritize transfer_out transaction
    # as it is the primary transaction for idempotency purposes
    transfer_out = transactions.find { |t| t.transaction_type == 'transfer_out' }
    transfer_out || transactions.first
  end

  def build_result_from_transaction(transaction)
    ServiceResult.new(
      success: transaction.status == 'completed',
      data: transaction,
      error: transaction.status == 'failed' ? 'Transaction previously failed' : nil
    )
  end
end
