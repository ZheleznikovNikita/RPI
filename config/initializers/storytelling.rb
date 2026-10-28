# Assign an adapter implementing #name, #model_identifier and #call(payload:).
# #call returns { "narration" => String, "summary" => String }.
# Keep credentials on the server; set network timeouts inside the adapter.
Rails.application.config.x.narration_provider = nil
