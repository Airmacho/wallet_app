# frozen_string_literal: true

Money.locale_backend = nil
Money.rounding_mode = BigDecimal::ROUND_HALF_UP
Money.default_currency = 'USD'

Money.default_bank = Money::Bank::VariableExchange.new

# KEY_POINT: in production, we should use external rate provider and background job to update rates
Money.default_bank.tap do |bank|
  bank.add_rate('USD', 'EUR', 0.85)
  bank.add_rate('EUR', 'USD', 1.18)
  bank.add_rate('USD', 'GBP', 0.73)
  bank.add_rate('GBP', 'USD', 1.37)
end