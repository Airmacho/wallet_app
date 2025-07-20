# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallet, type: :model do
  it 'correctly handles deposit and withdrawal operations' do
    wallet = create(:wallet, balance_cents: 1_000)

    wallet.deposit!(500)
    expect(wallet.balance_cents).to eq(1_500)

    wallet.withdraw!(300)
    expect(wallet.balance_cents).to eq(1_200)

    expect { wallet.withdraw!(2_000) }.to raise_error(Wallet::InsufficientFundsError)
  end
end
