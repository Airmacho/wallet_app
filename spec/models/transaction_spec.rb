# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Transaction, type: :model do
  it 'validates idempotency_key presence and allows duplicate keys for transfer pairs' do
    # Requires idempotency key
    transaction = build(:transaction, :deposit, idempotency_key: nil)
    expect(transaction).not_to be_valid

    # Allows duplicate keys for transfer pairs
    key = 'transfer-123'
    create(:transaction, :transfer_out, idempotency_key: key)
    transfer_in = build(:transaction, :transfer_in, idempotency_key: key)
    expect(transfer_in).to be_valid
  end
end
