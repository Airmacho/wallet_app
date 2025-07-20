# frozen_string_literal: true

# A standardized object for returning results from service objects.
ServiceResult = Struct.new(:success, :data, :error, keyword_init: true) do
  def success?
    success
  end

  def failure?
    !success?
  end
end
