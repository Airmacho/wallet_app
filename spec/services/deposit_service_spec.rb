# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DepositService do
  let(:user) { create(:user) }
  let(:wallet) { user.wallet }
  let(:amount_cents) { 10_000 }
  let(:idempotency_key) { 'deposit-test-key' }

  describe '#call' do
    context 'when deposit is successful' do
      it 'increases wallet balance by deposited amount' do
        initial_balance = wallet.balance_cents
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(initial_balance + amount_cents)
      end

      it 'creates completed deposit transaction with correct attributes' do
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call
        transaction = result.data

        expect(transaction).to be_a(Transaction)
        expect(transaction.transaction_type).to eq('deposit')
        expect(transaction.amount_cents).to eq(amount_cents)
        expect(transaction.currency).to eq(wallet.currency)
        expect(transaction.status).to eq('completed')
        expect(transaction.idempotency_key).to eq(idempotency_key)
        expect(transaction.wallet).to eq(wallet)
      end

      it 'handles zero initial balance deposits correctly' do
        expect(wallet.balance_cents).to eq(0)
        service = described_class.new(user: user, amount_cents: 5000, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(5000)
      end

      it 'handles multiple consecutive deposits correctly' do
        first_service = described_class.new(user: user, amount_cents: 3000, idempotency_key: 'first-deposit')
        second_service = described_class.new(user: user, amount_cents: 7000, idempotency_key: 'second-deposit')

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(10_000)
      end
    end

    context 'when idempotency is enforced' do
      it 'returns same transaction for duplicate idempotency key requests' do
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        first_result = service.call
        second_result = service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(first_result.data.id).to eq(second_result.data.id)
        expect(wallet.reload.balance_cents).to eq(amount_cents) # Only deposited once
      end

      it 'allows different deposits with different idempotency keys' do
        first_service = described_class.new(user: user, amount_cents: 2000, idempotency_key: 'key-1')
        second_service = described_class.new(user: user, amount_cents: 3000, idempotency_key: 'key-2')

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(first_result.data.id).not_to eq(second_result.data.id)
        expect(wallet.reload.balance_cents).to eq(5000)
      end
    end

    context 'when validation fails' do
      it 'rejects negative deposit amounts' do
        service = described_class.new(user: user, amount_cents: -1000, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects zero deposit amounts' do
        service = described_class.new(user: user, amount_cents: 0, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects non_integer deposit amounts' do
        service = described_class.new(user: user, amount_cents: 100.5, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects string deposit amounts' do
        service = described_class.new(user: user, amount_cents: '1000', idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects nil deposit amounts' do
        service = described_class.new(user: user, amount_cents: nil, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(0)
      end
    end

    context 'when database transaction fails' do
      it 'marks transaction as failed when wallet deposit raises exception' do
        allow_any_instance_of(Wallet).to receive(:deposit!).and_raise(StandardError, 'Database error')
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to eq('Database error')
        expect(wallet.reload.balance_cents).to eq(0)

        failed_transaction = Transaction.find_by(idempotency_key: idempotency_key)
        expect(failed_transaction).to be_present
        expect(failed_transaction.status).to eq('failed')
        expect(failed_transaction.transaction_type).to eq('deposit')
        expect(failed_transaction.amount_cents).to eq(amount_cents)
        expect(failed_transaction.metadata['failure_reason']).to eq('Database error')
        expect(failed_transaction.metadata['failed_at']).to be_present
      end

      it 'returns failure result when transaction creation fails' do
        allow(Transaction).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(wallet.reload.balance_cents).to eq(0)
      end
    end

    context 'when handling large deposit amounts' do
      it 'processes very large deposits within integer limits' do
        large_amount = 999_999_999
        service = described_class.new(user: user, amount_cents: large_amount, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(large_amount)
      end
    end

    context 'when handling concurrent deposits with different users' do
      it 'processes deposits for different users independently' do
        other_user = create(:user)
        first_service = described_class.new(user: user, amount_cents: 5000, idempotency_key: 'user-1-deposit')
        second_service = described_class.new(user: other_user, amount_cents: 3000, idempotency_key: 'user-2-deposit')

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(user.wallet.reload.balance_cents).to eq(5000)
        expect(other_user.wallet.reload.balance_cents).to eq(3000)
      end
    end
  end
end
