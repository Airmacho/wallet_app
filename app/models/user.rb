# frozen_string_literal: true

class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  has_one :wallet, dependent: :destroy

  before_create :generate_api_key
  after_create :create_wallet

  private

  def generate_api_key
    self.api_key = SecureRandom.hex(24)
  end

  def create_wallet
    Wallet.create!(user: self, balance_cents: 0, currency: 'USD')
  end
end
