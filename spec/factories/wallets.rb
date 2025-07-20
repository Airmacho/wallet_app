# frozen_string_literal: true

FactoryBot.define do
  factory :wallet do
    association :user, factory: %i[user without_wallet]
    balance_cents { 0 }
    currency { 'USD' }
  end
end
