class Browser
  include Singleton

  def html_to_pdf(file_root, basename, filename: nil, content: nil)
    content = File.read(filename) unless filename.nil?
    html_filename = "#{file_root}/html/#{basename}.html"
    pdf_filename = "#{file_root}/pdf/#{basename}.pdf"
    File.write(html_filename, content)
    page = browser.create_page
    page.go_to("file://#{html_filename}")
    page.pdf(
      path: pdf_filename,
      landscape: true,
      format: :A4
    )
    browser.reset
  end

  def quit
    browser.quit
  end

  def x
    p "!!! x"
  end

  private

  # def initialize
  # end

  def browser
    @browser ||= Ferrum::Browser.new(
      browser_options: {
        "generate-pdf-document-outline": true
      }
    )
  end
end