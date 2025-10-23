class Browser
  include Singleton

  def html_to_pdf(html_filename, pdf_filename, landscape: true, content: nil)
    p "!!! html_to_pdf #{html_filename} #{pdf_filename}"
    # raise "Browser:html_to_pdf missing file_root" if @file_root.nil?
    if content.present?
      raise "Browser:html_to_pdf content provided but HTML file already exists #{html_filename}" if File.exist?(html_filename)
      File.write(html_filename, content)
    else
      raise "Browser:html_to_pdf HTML file does not exist #{html_filename}" unless File.exist?(html_filename)
    end
    page = browser.create_page
    page.go_to("file://#{html_filename}")
    p "!!! current_title #{page.current_title }"
    browser.network.wait_for_idle(timeout: 60)
    page.pdf(
      path: pdf_filename,
      author: "Deddington History",
      landscape: landscape,
      format: :A4
    )
    browser.reset
  end

  def with_root(file_root)
    # @file_root = file_root
    begin
      yield
    rescue => e
      puts e.backtrace
      raise "Browser:with_root failed #{e.inspect}"
    ensure
      browser.quit
      @browser = nil
      # @file_root = nil
    end
  end

  private

  def browser
    @browser ||= Ferrum::Browser.new(
      browser_options: {
        timeout: 90,
        protocol_timeout: 60,
        with_root: true,
        "user-agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36"
      }
    )
  end
end