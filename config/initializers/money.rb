# frozen_string_literal: true

# Money gem configuration
Money.locale_backend = nil
Money.rounding_mode = BigDecimal::ROUND_HALF_UP
Money.default_currency = 'USD'

# Configure exchange rates for currency conversion
Money.default_bank = Money::Bank::VariableExchange.new

# Simple exchange rates for demo/development
Money.default_bank.tap do |bank|
  bank.add_rate('USD', 'EUR', 0.85)
  bank.add_rate('EUR', 'USD', 1.18)
  bank.add_rate('USD', 'GBP', 0.73)
  bank.add_rate('GBP', 'USD', 1.37)
end

# TODO: Production - use external rate provider and background job to update rates
