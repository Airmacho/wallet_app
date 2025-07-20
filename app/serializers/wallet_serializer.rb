# frozen_string_literal: true

class WalletSerializer < ActiveModel::Serializer
  attributes :id, :balance_cents, :currency
end
