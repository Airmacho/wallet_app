# frozen_string_literal: true

# config/initializers/redis.rb

# This configuration sets up a Redis client instance for the application.
# Using a constant provides a clean way to access Redis across the application
# while avoiding global variables.

REDIS_CLIENT = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
