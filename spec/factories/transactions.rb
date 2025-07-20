# frozen_string_literal: true

FactoryBot.define do
  factory :transaction do
    association :wallet
    amount_cents { 10_000 }
    currency { 'USD' }
    status { 'pending' }
    idempotency_key { SecureRandom.uuid }

    trait :deposit do
      transaction_type { 'deposit' }
    end

    trait :withdrawal do
      transaction_type { 'withdrawal' }
    end

    trait :transfer_in do
      transaction_type { 'transfer_in' }
    end

    trait :transfer_out do
      transaction_type { 'transfer_out' }
    end

    trait :completed do
      status { 'completed' }
    end

    trait :failed do
      status { 'failed' }
    end
  end
end
