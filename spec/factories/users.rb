# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.unique.email }

    trait :without_wallet do
      after(:build) do |user|
        user.define_singleton_method(:create_wallet) { nil }
      end
    end
  end
end
