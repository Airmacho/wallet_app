# frozen_string_literal: true

class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.references :wallet, null: false, foreign_key: true
      t.string :transaction_type, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: 'USD'
      t.string :status, null: false, default: 'pending'
      t.string :idempotency_key
      t.jsonb :metadata

      t.timestamps
    end

    add_index :transactions, :idempotency_key, where: 'idempotency_key IS NOT NULL'
    add_index :transactions, :status
    add_index :transactions, :created_at
  end
end
