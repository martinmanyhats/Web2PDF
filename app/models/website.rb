class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  def scrape(force: false)
    p "!!! Website::scrape #{inspect}"
    webpage = Webpage.find_or_initialize_by(website: self, url: url) do |page|
      page.status = "unscraped"
      page.website = self
    end
    self.root_webpage = webpage
    save!
    webpage.scrape(force: force)
    page_count = 0
    loop do
      unscraped_webpages = Webpage.where(status: "unscraped")
      p "!!! Website::scrape count #{unscraped_webpages.count}"
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |page|
        page.scrape(force: force)
        page_count += 1
        return if page_count > 50
      end
    end
  end

  def generate
    p "!!! Website::generate"
    File.open("/tmp/dh.html", "wb") do |file|
      webpages.reject { |page| page.status != "scraped"}.
        each { |page| page.generate_html(file) }
      browser = Ferrum::Browser.new
      page = browser.create_page
      page.go_to("file:///tmp/dh.html")
      page.pdf(
        path: "/tmp/dh.pdf",
        landscape: true,
        format: :A4,
      )
      file.close
      browser.reset
      browser.quit
    end
  end

  def generate2(format: "pdf")
    collate_pdfs("tmp/dh.pdf", generate_pdfs)
  end

  def generate_pdfs
    scraped_pages = Webpage.where(status: "scraped")
    root_pdf_filename = root_webpage.generate_pdf
    pdf_filenames = scraped_pages.map do |page|
      page.generate_pdf unless page == root_webpage
    end.compact
    pdf_filenames.insert(0, root_pdf_filename)
    p "!!! pdf_filenames #{pdf_filenames.inspect}"
    pdf_filenames
  end

  def collate_pdfs(collated_filename, partial_filenames)
    p "!!! #{partial_filenames.join(" ")} > #{collated_filename}"
    system("pdftk #{partial_filenames.join(" ")} cat output #{collated_filename}")
  end

  def url_internal?(url2)
    # p "!!! url #{url} url2 #{url2} #{url2.starts_with?(url)}"
    url2.starts_with?(url)
  end
end
