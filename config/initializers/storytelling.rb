# Assign an adapter implementing #name, #model_identifier and #call(payload:).
# #call returns { "narration" => String, "summary" => String }.
# Keep credentials on the server; set network timeouts inside the adapter.
# CI must never make paid requests even if the shell has a real key.
Rails.application.config.to_prepare do
  key = ENV["POLZA_API_KEY"].to_s.strip
  Rails.application.config.x.narration_provider =
    if key.present? && !Rails.env.test?
      Storytelling::DeepseekProvider.new(api_key: key)
    end
end
