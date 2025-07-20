# frozen_string_literal: true

unless Rails.env.production?
  # User 1: Primary test user (USD wallet)
  User.find_or_create_by!(email: 'user1@example.com')

  # User 2: Secondary test user for transfer testing (USD wallet)
  User.find_or_create_by!(email: 'user2@example.com')

  # User 3: Multi-currency test user (EUR wallet)
  eur_user = User.find_or_create_by!(email: 'user3@example.com')
  # Update wallet currency to EUR for currency conversion testing
  eur_user.wallet.update!(currency: 'EUR') if eur_user.wallet.currency != 'EUR'
end
