# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Wallet API', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:headers) { { 'X-User-API-Key' => user.api_key, 'Content-Type' => 'application/json' } }

  def json_response
    response.parsed_body
  end

  describe 'POST /v1/deposits' do
    it 'successfully deposits money into user wallet' do
      initial_balance = user.wallet.balance_cents

      post '/v1/deposits',
           params: { deposit: { amount_cents: 10_000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'deposit-1')

      expect(response).to have_http_status(:created)
      expect(json_response['transaction_type']).to eq('deposit')
      expect(json_response['amount_cents']).to eq(10_000)
      expect(json_response['status']).to eq('completed')
      expect(json_response['wallet_id']).to eq(user.wallet.id)
      expect(user.wallet.reload.balance_cents).to eq(initial_balance + 10_000)
    end

    it 'handles idempotent requests by returning same transaction' do
      key = 'deposit-idempotent'
      params = { deposit: { amount_cents: 5000 } }.to_json
      headers_with_key = headers.merge('Idempotency-Key' => key)

      # First request
      post '/v1/deposits', params: params, headers: headers_with_key
      first_id = json_response['id']

      # Second request with same key
      post '/v1/deposits', params: params, headers: headers_with_key
      second_id = json_response['id']

      expect(first_id).to eq(second_id)
      expect(user.wallet.reload.balance_cents).to eq(5000) # Only added once
    end

    it 'returns unauthorized when API key is missing' do
      post '/v1/deposits',
           params: { deposit: { amount_cents: 1000 } }.to_json,
           headers: { 'Content-Type' => 'application/json', 'Idempotency-Key' => 'test' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns bad request when idempotency key is missing' do
      post '/v1/deposits',
           params: { deposit: { amount_cents: 1000 } }.to_json,
           headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(json_response['error']).to eq('Idempotency-Key header is missing')
    end

    it 'rejects negative deposit amounts' do
      post '/v1/deposits',
           params: { deposit: { amount_cents: -1000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'negative')

      expect(response).to have_http_status(:bad_request)
      expect(json_response['error']).to include('Amount must be positive')
    end
  end

  describe 'POST /v1/withdrawals' do
    before { user.wallet.deposit!(10_000) }

    it 'successfully withdraws money from user wallet' do
      post '/v1/withdrawals',
           params: { withdrawal: { amount_cents: 3000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'withdrawal-1')

      expect(response).to have_http_status(:created)
      expect(user.wallet.reload.balance_cents).to eq(7000)
      expect(json_response['transaction_type']).to eq('withdrawal')
      expect(json_response['amount_cents']).to eq(3000)
    end

    it 'rejects withdrawal when insufficient balance' do
      post '/v1/withdrawals',
           params: { withdrawal: { amount_cents: 20_000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'insufficient')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['error']).to include('Insufficient balance')
      expect(user.wallet.reload.balance_cents).to eq(10_000) # Unchanged
    end
  end

  describe 'POST /v1/transfers' do
    before { user.wallet.deposit!(10_000) }

    it 'successfully transfers money between users' do
      post '/v1/transfers',
           params: { transfer: { to_email: other_user.email, amount_cents: 4000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'transfer-1')

      expect(response).to have_http_status(:created)
      expect(user.wallet.reload.balance_cents).to eq(6000)
      expect(other_user.wallet.reload.balance_cents).to eq(4000)
      expect(json_response['transaction_type']).to eq('transfer_out')
    end

    it 'creates linked transfer_out and transfer_in transactions' do
      post '/v1/transfers',
           params: { transfer: { to_email: other_user.email, amount_cents: 2000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'transfer-linked')

      transfer_out = user.wallet.transactions.where(transaction_type: 'transfer_out').last
      transfer_in = other_user.wallet.transactions.where(transaction_type: 'transfer_in').last

      expect(transfer_out.idempotency_key).to eq(transfer_in.idempotency_key)
      expect(transfer_out.amount_cents).to eq(2000)
      expect(transfer_in.amount_cents).to eq(2000)
    end

    it 'converts currency during cross-currency transfers' do
      eur_user = create(:user)
      eur_user.wallet.update!(currency: 'EUR')

      post '/v1/transfers',
           params: { transfer: { to_email: eur_user.email, amount_cents: 1000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'currency-transfer')

      expect(response).to have_http_status(:created)
      expect(user.wallet.reload.balance_cents).to eq(9000)
      expect(eur_user.wallet.reload.balance_cents).to eq(850)
    end

    it 'returns not found when transferring to non-existent user' do
      post '/v1/transfers',
           params: { transfer: { to_email: 'nonexistent@example.com', amount_cents: 1000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'invalid-user')

      expect(response).to have_http_status(:not_found)
      expect(json_response['error']).to eq('Recipient user not found')
    end

    it 'rejects transfer to same user (self-transfer)' do
      post '/v1/transfers',
           params: { transfer: { to_email: user.email, amount_cents: 1000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'self-transfer')

      expect(response).to have_http_status(:bad_request)
      expect(json_response['error']).to include('Cannot transfer to self')
    end
  end

  describe 'GET /v1/me/wallet' do
    it 'returns current wallet balance and details' do
      post '/v1/deposits',
           params: { deposit: { amount_cents: 15_000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'deposit-for-balance')

      get '/v1/me/wallet', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['balance_cents']).to eq(15_000)
      expect(json_response['currency']).to eq('USD')
      expect(json_response['id']).to eq(user.wallet.id)
    end

    it 'returns unauthorized when accessing wallet without API key' do
      get '/v1/me/wallet'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /v1/me/transactions' do
    it 'returns transaction history in descending chronological order' do
      post '/v1/deposits',
           params: { deposit: { amount_cents: 5000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'deposit-for-history')

      sleep(0.01) # Ensure different timestamps

      post '/v1/withdrawals',
           params: { withdrawal: { amount_cents: 1000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'withdrawal-for-history')

      get '/v1/me/transactions', headers: headers

      expect(response).to have_http_status(:ok)
      transactions = json_response

      expect(transactions.size).to eq(2)
      expect(transactions.first['transaction_type']).to eq('withdrawal')
      expect(transactions.last['transaction_type']).to eq('deposit')
    end

    it 'includes all required fields in transaction response' do
      post '/v1/deposits',
           params: { deposit: { amount_cents: 2000 } }.to_json,
           headers: headers.merge('Idempotency-Key' => 'deposit-for-fields')

      get '/v1/me/transactions', headers: headers

      transaction = json_response.first
      required_fields = %w[id transaction_type amount_cents currency status created_at]

      required_fields.each do |field|
        expect(transaction).to have_key(field)
      end
    end

    it 'returns unauthorized when accessing transactions without API key' do
      get '/v1/me/transactions'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
