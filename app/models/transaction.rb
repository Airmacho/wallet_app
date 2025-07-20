# frozen_string_literal: true

# ThinkingProcess: This model provides core Event Sourcing benefits:
# - Immutable records (transactions never updated after completion)
# - Failed operations are recorded with failure reasons in metadata
# - Complete operation timeline through transaction history
# - Consistent pattern: all services (deposit/withdraw/transfer) record attempts
# - Audit trail for compliance and debugging
#
# Pattern used:
# 1. Create transaction with status: 'pending'
# 2. Execute business logic
# 3a. Success -> update status: 'completed'
# 3b. Failure -> update status: 'failed' + metadata: { failure_reason: "..." }
#
# Full Event Sourcing not implemented because:
# - ES best practice uses specialized stores (EventStore, Kafka)
# - PostgreSQL not optimized for append-only event streams
# - Current requirements satisfied without full ES overhead
class Transaction < ApplicationRecord
  TRANSACTION_TYPES = %w[deposit withdrawal transfer_in transfer_out].freeze
  STATUSES = %w[pending completed failed].freeze

  belongs_to :wallet
  monetize :amount_cents, with_model_currency: :currency

  validates :transaction_type, presence: true, inclusion: { in: TRANSACTION_TYPES }
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true

  scope :deposits, -> { where(transaction_type: 'deposit') }
  scope :withdrawals, -> { where(transaction_type: 'withdrawal') }
  scope :transfers, -> { where(transaction_type: %w[transfer_in transfer_out]) }
  scope :completed, -> { where(status: 'completed') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
end
