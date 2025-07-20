# frozen_string_literal: true

class Wallet < ApplicationRecord
  class InsufficientFundsError < StandardError; end

  belongs_to :user
  monetize :balance_cents, with_model_currency: :currency

  validates :balance_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :user_id, uniqueness: true

  has_many :transactions, dependent: :destroy

  def deposit!(amount_cents)
    with_lock do
      self.balance_cents += amount_cents
      save!
    end
  end

  def withdraw!(amount_cents)
    with_lock do
      raise InsufficientFundsError, 'Insufficient balance' if balance_cents < amount_cents

      self.balance_cents -= amount_cents
      save!
    end
  end
end
