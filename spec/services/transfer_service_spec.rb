# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransferService do
  let(:from_user) { create(:user) }
  let(:to_user) { create(:user) }
  let(:from_wallet) { from_user.wallet }
  let(:to_wallet) { to_user.wallet }
  let(:amount_cents) { 5000 }
  let(:idempotency_key) { 'transfer-test-key' }

  before do
    from_wallet.deposit!(10000)
  end

  describe '#call' do
    context 'when transfer is successful with same currency' do
      it 'decreases sender balance and increases recipient balance by same amount' do
        from_initial = from_wallet.balance_cents
        to_initial = to_wallet.balance_cents

        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be true
        expect(from_wallet.reload.balance_cents).to eq(from_initial - amount_cents)
        expect(to_wallet.reload.balance_cents).to eq(to_initial + amount_cents)
      end

      it 'creates transfer_out transaction for sender with correct attributes' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        result = service.call
        transfer_out = result.data

        expect(transfer_out).to be_a(Transaction)
        expect(transfer_out.transaction_type).to eq('transfer_out')
        expect(transfer_out.amount_cents).to eq(amount_cents)
        expect(transfer_out.currency).to eq(from_wallet.currency)
        expect(transfer_out.status).to eq('completed')
        expect(transfer_out.idempotency_key).to eq(idempotency_key)
        expect(transfer_out.wallet).to eq(from_wallet)
      end

      it 'creates transfer_in transaction for recipient with matching idempotency key' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        service.call

        transfer_in = to_wallet.transactions.where(transaction_type: 'transfer_in').last
        expect(transfer_in).to be_present
        expect(transfer_in.transaction_type).to eq('transfer_in')
        expect(transfer_in.amount_cents).to eq(amount_cents)
        expect(transfer_in.currency).to eq(to_wallet.currency)
        expect(transfer_in.status).to eq('completed')
        expect(transfer_in.idempotency_key).to eq(idempotency_key)
        expect(transfer_in.wallet).to eq(to_wallet)
      end

      it 'allows transfer of entire sender balance' do
        total_balance = from_wallet.balance_cents
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: total_balance,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be true
        expect(from_wallet.reload.balance_cents).to eq(0)
        expect(to_wallet.reload.balance_cents).to eq(total_balance)
      end
    end

    context 'when transfer involves currency conversion' do
      before do
        to_wallet.update!(currency: 'EUR')
      end

      it 'converts amount between different currencies using exchange rates' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 1000,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be true
        expect(from_wallet.reload.balance_cents).to eq(9000)
        expect(to_wallet.reload.balance_cents).to eq(850)
      end

      it 'creates transactions with correct amounts in respective currencies' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 2000,
          idempotency_key: idempotency_key
        )

        result = service.call
        transfer_out = result.data
        transfer_in = to_wallet.transactions.where(transaction_type: 'transfer_in').last

        expect(transfer_out.amount_cents).to eq(2000)
        expect(transfer_out.currency).to eq('USD')
        expect(transfer_in.amount_cents).to eq(1700)
        expect(transfer_in.currency).to eq('EUR')
      end

      it 'handles unsupported currency conversion' do
        to_wallet.update!(currency: 'INVALID')
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 1000,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Unknown currency')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end
    end

    context 'when idempotency is enforced' do
      it 'returns same transfer_out transaction for duplicate idempotency key requests' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        first_result = service.call
        second_result = service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(first_result.data.id).to eq(second_result.data.id)
        expect(from_wallet.reload.balance_cents).to eq(5000)
        expect(to_wallet.reload.balance_cents).to eq(5000)
      end

      it 'allows different transfers with different idempotency keys' do
        first_service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 2000,
          idempotency_key: 'key-1'
        )
        second_service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 3000,
          idempotency_key: 'key-2'
        )

        first_result = first_service.call
        second_result = second_service.call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(first_result.data.id).not_to eq(second_result.data.id)
        expect(from_wallet.reload.balance_cents).to eq(5000)
        expect(to_wallet.reload.balance_cents).to eq(5000)
      end
    end

    context 'when insufficient funds' do
      it 'rejects transfer when sender has insufficient balance' do
        from_wallet.update!(balance_cents: 1000)
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 2000,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Insufficient balance')
        expect(from_wallet.reload.balance_cents).to eq(1000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects transfer from empty sender wallet' do
        from_wallet.update!(balance_cents: 0)
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 100,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include('Insufficient balance')
        expect(from_wallet.reload.balance_cents).to eq(0)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end
    end

    context 'when validation fails' do
      it 'rejects negative transfer amounts' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: -1000,
          idempotency_key: idempotency_key
        )

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects zero transfer amounts' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 0,
          idempotency_key: idempotency_key
        )

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects self_transfer' do
        service = described_class.new(
          from_user: from_user,
          to_user: from_user,
          amount_cents: 1000,
          idempotency_key: idempotency_key
        )

        expect { service.call }.to raise_error(ArgumentError, 'Cannot transfer to self')
        expect(from_wallet.reload.balance_cents).to eq(10000)
      end

      it 'rejects non_integer transfer amounts' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 100.5,
          idempotency_key: idempotency_key
        )

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects string transfer amounts' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: '1000',
          idempotency_key: idempotency_key
        )

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end

      it 'rejects nil transfer amounts' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: nil,
          idempotency_key: idempotency_key
        )

        expect { service.call }.to raise_error(ArgumentError, 'Amount must be positive')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end
    end

    context 'when database transaction fails' do
      it 'returns failure result when wallet operations raise exception' do
        allow_any_instance_of(Wallet).to receive(:withdraw!).and_raise(StandardError, 'Insufficient funds')
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to eq('Insufficient funds')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end

      it 'returns failure result when wallet operations raise exception' do
        allow_any_instance_of(Wallet).to receive(:withdraw!).and_raise(StandardError, 'Insufficient funds')
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be false
        expect(result.error).to eq('Insufficient funds')
        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)

        failed_transaction = from_wallet.transactions.find_by(idempotency_key: idempotency_key)
        expect(failed_transaction.status).to eq('failed')
        expect(failed_transaction.failed_reason).to eq('Insufficient funds')
      end
    end

    context 'when handling large transfer amounts' do
      it 'processes large transfers within available balance' do
        from_wallet.update!(balance_cents: 1000000000)
        large_amount = 999999999
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: large_amount,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be true
        expect(from_wallet.reload.balance_cents).to eq(1000000000 - large_amount)
        expect(to_wallet.reload.balance_cents).to eq(large_amount)
      end
    end

    context 'when handling concurrent transfers involving same wallets' do
      it 'prevents race conditions using fixed order locking' do
        other_user = create(:user)
        other_user.wallet.deposit!(5000)

        # KEY_POINT: Create transfers between the same wallets in different directions to simulate circular deadlocks
        service1 = described_class.new(
          from_user: from_user,
          to_user: other_user,
          amount_cents: 3000,
          idempotency_key: 'transfer-1'
        )
        service2 = described_class.new(
          from_user: other_user,
          to_user: from_user,
          amount_cents: 2000,
          idempotency_key: 'transfer-2'
        )

        result1 = service1.call
        result2 = service2.call

        expect(result1.success?).to be true
        expect(result2.success?).to be true
        expect(from_wallet.reload.balance_cents).to eq(9000)
        expect(other_user.wallet.reload.balance_cents).to eq(6000)
      end
    end

    context 'when transfer creates linked transaction pair' do
      it 'ensures both transactions share the same idempotency key' do
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        result = service.call

        transfer_out = result.data
        transfer_in = to_wallet.transactions.where(transaction_type: 'transfer_in').last

        expect(transfer_out.idempotency_key).to eq(transfer_in.idempotency_key)
        expect(transfer_out.idempotency_key).to eq(idempotency_key)
      end

      it 'records failed transfer attempt when transfer_in creation fails' do
        allow(Transaction).to receive(:create!).and_call_original
        allow(Transaction).to receive(:create!).with(
          hash_including(transaction_type: 'transfer_in')
        ).and_raise(ActiveRecord::RecordInvalid)

        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: amount_cents,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be false

        failed_transaction = from_wallet.transactions.find_by(idempotency_key: idempotency_key)
        expect(failed_transaction).to be_present
        expect(failed_transaction.status).to eq('failed')
        expect(failed_transaction.failed_reason).to be_present

        expect(to_wallet.transactions.where(idempotency_key: idempotency_key)).to be_empty

        expect(from_wallet.reload.balance_cents).to eq(10000)
        expect(to_wallet.reload.balance_cents).to eq(0)
      end
    end

    context 'when handling edge cases in currency conversion' do
      it 'handles fractional currency conversion results correctly' do
        to_wallet.update!(currency: 'EUR')
        service = described_class.new(
          from_user: from_user,
          to_user: to_user,
          amount_cents: 333,
          idempotency_key: idempotency_key
        )

        result = service.call

        expect(result.success?).to be true
        expect(from_wallet.reload.balance_cents).to eq(9667)
        expect(to_wallet.reload.balance_cents).to be_a(Integer)
        expect(to_wallet.reload.balance_cents).to eq(283)
      end
    end
  end

  describe '#convert_currency' do
    let(:service) do
      described_class.new(from_user: from_user, to_user: to_user, amount_cents: 1000, idempotency_key: 'test')
    end

    it 'returns same amount for same currency conversion' do
      result = service.send(:convert_currency, 1000, 'USD', 'USD')
      expect(result).to eq(1000)
    end

    it 'converts between different currencies using Money gem' do
      result = service.send(:convert_currency, 1000, 'USD', 'EUR')
      expect(result).to eq(850)
    end

    it 'raises error for unsupported currency pairs' do
      expect do
        service.send(:convert_currency, 1000, 'USD', 'INVALID')
      end.to raise_error(ArgumentError, /Unknown currency/)
    end
  end
end
