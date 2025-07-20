# frozen_string_literal: true

class CreateWallets < ActiveRecord::Migration[7.1]
  def change
    create_table :wallets do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.bigint :balance_cents, null: false, default: 0
      t.string :currency, null: false, default: 'USD'

      t.timestamps
    end
  end
end
