# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  it 'automatically creates wallet and API key on user creation' do
    user = create(:user)

    expect(user.wallet).to be_present
    expect(user.wallet.balance_cents).to eq(0)
    expect(user.api_key).to be_present
  end
end
