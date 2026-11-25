require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"
require "capybara/selenium/driver_specializations/edge_driver"

# Capybara 3.40 sends origin="*" after navigating to about:blank. Chrome 158
# rejects that value. Clear the actual test origin instead, retaining isolation.
module ChromiumStorageReset
  def reset!
    url = @browser&.current_url
    if url&.start_with?("http://", "https://")
      uri = URI.parse(url)
      @rpi_storage_origin = "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end
    super
  end

  private

  def execute_cdp(command, params = {})
    if command == "Storage.clearDataForOrigin" && params[:origin] == "*"
      return super("Network.clearBrowserCookies", {}) unless @rpi_storage_origin

      params = params.merge(origin: @rpi_storage_origin)
    end
    super(command, params)
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromiumStorageReset)
Capybara::Selenium::Driver::EdgeDriver.prepend(ChromiumStorageReset)
