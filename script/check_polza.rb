# Run with: ruby bin/rails runner script/check_polza.rb
# Uses the current shell's key; does not create users, sessions or story records.
key = ENV["POLZA_API_KEY"].to_s.strip
if key.empty?
  warn "POLZA_API_KEY is missing in this PowerShell window."
  exit 2
end

puts "Testing Polza / #{Storytelling::DeepseekProvider::MODEL} / #{Storytelling::DeepseekProvider::ROUTE}"
puts "One real API request will be made. The provider may charge for generation."
begin
  result = Storytelling::DeepseekProvider.new(api_key: key).call(payload: {
    "command" => "Осмотреть ворота", "scene" => StartingScenes::DEFAULT.fetch(:intro),
    "summary" => "", "history" => []
  })
  puts "OK: API and game response contract work."
  puts "Narration length: #{result.fetch('narration').length}"
rescue Storytelling::DeepseekProvider::Error => error
  warn "Diagnostic: #{error.diagnostic_code}"
  warn "Provider explanation: #{error.detail}" if error.detail
  exit 1
rescue StandardError => error
  warn "Diagnostic: #{error.class.name} (details hidden to protect credentials)"
  exit 1
end
