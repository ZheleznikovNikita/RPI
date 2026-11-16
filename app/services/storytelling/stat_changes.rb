module Storytelling
  module StatChanges
    LIMITS = { "health_delta" => -30..20, "stamina_delta" => -40..30 }.freeze

    # Old saved responses and offline adapters predate stat changes.
    def self.parse(response, required: false)
      raise ArgumentError, "Invalid stat changes" unless response.is_a?(Hash)

      return LIMITS.transform_values { 0 } if !required && LIMITS.keys.none? { |key| response.key?(key) }

      LIMITS.to_h do |key, range|
        value = response[key]
        raise ArgumentError, "Invalid stat changes" unless value.is_a?(Integer) && range.cover?(value)

        [ key, value ]
      end
    end
  end
end
