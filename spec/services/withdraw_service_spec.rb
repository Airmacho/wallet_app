# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WithdrawService do
  let(:user) { create(:user) }
  let(:wallet) { user.wallet }
  let(:amount_cents) { 5000 }
  let(:idempotency_key) { 'withdraw-test-key' }

  before do
    wallet.deposit!(10_000)
  end

  describe '#call' do
    context 'when withdrawal is successful' do
      it 'decreases wallet balance by withdrawn amount' do
        initial_balance = wallet.balance_cents
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(initial_balance - amount_cents)
      end

      it 'creates completed withdrawal transaction with correct attributes' do
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call
        transaction = result.data

        expect(transaction).to be_a(Transaction)
        expect(transaction.transaction_type).to eq('withdrawal')
        expect(transaction.amount_cents).to eq(amount_cents)
        expect(transaction.currency).to eq(wallet.currency)
        expect(transaction.status).to eq('completed')
        expect(transaction.idempotency_key).to eq(idempotency_key)
        expect(transaction.wallet).to eq(wallet)
      end

      it 'allows withdrawal of entire wallet balance' do
        total_balance = wallet.balance_cents
        service = described_class.new(user: user, amount_cents: total_balance, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(0)
      end

      it 'handles multiple consecutive withdrawals correctly' do
        first_service = described_class.new(user: user, amount_cents: 2000, idempotency_key: 'first-withdrawal')
        second_service = described_class.new(user: user, amount_cents: 3000, idempotency_key: 'second-withdrawal')

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(5000)
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
        expect(wallet.reload.balance_cents).to eq(5000)
      end

      it 'allows different withdrawals with different idempotency keys' do
        first_service = described_class.new(user: user, amount_cents: 1000, idempotency_key: 'key-1')
        second_service = described_class.new(user: user, amount_cents: 2000, idempotency_key: 'key-2')

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(first_result.data.id).not_to eq(second_result.data.id)
        expect(wallet.reload.balance_cents).to eq(7000)
      end
    end

    context 'when insufficient funds' do
      it 'rejects withdrawal when amount exceeds balance' do
        wallet.update!(balance_cents: 1000)
        service = described_class.new(user: user, amount_cents: 2000, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Insufficient balance')
        expect(wallet.reload.balance_cents).to eq(1000)
      end

      it 'rejects withdrawal from empty wallet' do
        wallet.update!(balance_cents: 0)
        service = described_class.new(user: user, amount_cents: 100, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Insufficient balance')
        expect(wallet.reload.balance_cents).to eq(0)
      end

      it 'returns failure result when insufficient funds' do
        wallet.update!(balance_cents: 500)
        service = described_class.new(user: user, amount_cents: 1000, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Insufficient balance')
      end
    end

    context 'when validation fails' do
      it 'rejects negative withdrawal amounts with descriptive error' do
        service = described_class.new(user: user, amount_cents: -1000, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(10_000)
      end

      it 'rejects zero withdrawal amounts with descriptive error' do
        service = described_class.new(user: user, amount_cents: 0, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(10_000)
      end

      it 'rejects non-integer amounts with descriptive error' do
        service = described_class.new(user: user, amount_cents: 100.5, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(10_000)
      end

      it 'rejects string amounts with descriptive error' do
        service = described_class.new(user: user, amount_cents: '1000', idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(10_000)
      end

      it 'rejects nil amounts with descriptive error' do
        service = described_class.new(user: user, amount_cents: nil, idempotency_key: idempotency_key)

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(wallet.reload.balance_cents).to eq(10_000)
      end
    end

    context 'when database transaction fails' do
      it 'marks transaction as failed when wallet withdrawal raises exception' do
        allow_any_instance_of(Wallet).to receive(:withdraw!).and_raise(StandardError, 'Database error')
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to eq('Database error')
        expect(wallet.reload.balance_cents).to eq(10_000)

        failed_transaction = Transaction.find_by(idempotency_key: idempotency_key)
        expect(failed_transaction).to be_present
        expect(failed_transaction.status).to eq('failed')
        expect(failed_transaction.transaction_type).to eq('withdrawal')
        expect(failed_transaction.amount_cents).to eq(amount_cents)
        expect(failed_transaction.metadata['failure_reason']).to eq('Database error')
        expect(failed_transaction.metadata['failed_at']).to be_present
      end

      it 'returns failure result when transaction creation fails' do
        allow(Transaction).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
        service = described_class.new(user: user, amount_cents: amount_cents, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be false
        expect(wallet.reload.balance_cents).to eq(10_000)
      end
    end

    context 'when handling large withdrawal amounts' do
      it 'successfully processes large withdrawals within available balance' do
        wallet.update!(balance_cents: 1_000_000_000)
        large_amount = 999_999_999
        service = described_class.new(user: user, amount_cents: large_amount, idempotency_key: idempotency_key)

        result = service.call

        expect(result.success?).to be true
        expect(wallet.reload.balance_cents).to eq(1_000_000_000 - large_amount)
      end
    end

    context 'when handling concurrent withdrawals with different users' do
      it 'processes withdrawals for different users independently' do
        other_user = create(:user)
        other_user.wallet.deposit!(8000)

        first_service = described_class.new(user: user, amount_cents: 3000, idempotency_key: 'user-1-withdrawal')
        second_service = described_class.new(user: other_user, amount_cents: 2000, idempotency_key: 'user-2-withdrawal')

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(user.wallet.reload.balance_cents).to eq(7000)
        expect(other_user.wallet.reload.balance_cents).to eq(6000)
      end
    end

    context 'when wallet balance changes between validation and execution' do
      it 'handles race condition where balance decreases during transaction' do
        allow_any_instance_of(Wallet).to receive(:withdraw!) do |wallet_instance|
          wallet_instance.update!(balance_cents: 100)
          raise Wallet::InsufficientFundsError, 'Insufficient balance after concurrent operation'
        end

        service = described_class.new(user: user, amount_cents: 5000, idempotency_key: idempotency_key)
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Insufficient balance after concurrent operation')

        failed_transaction = Transaction.find_by(idempotency_key: idempotency_key)
        if failed_transaction
          expect(failed_transaction.status).to eq('failed')
          expect(failed_transaction.metadata['failure_reason']).to include('Insufficient balance')
        end
      end
    end
  end
end
