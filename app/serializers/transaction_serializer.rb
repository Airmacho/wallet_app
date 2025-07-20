# frozen_string_literal: true

class TransactionSerializer < ActiveModel::Serializer
  attributes :id, :wallet_id, :transaction_type, :amount_cents, :currency, :status, :created_at, :failed_reason
end
