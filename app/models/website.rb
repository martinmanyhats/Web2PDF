class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  def scrape(force: false, page_limit: 20)
    p "!!! Website::scrape #{inspect}"
    self.root_webpage = Webpage.find_or_initialize_by(url: url) do |page|
      page.website = self
      page.status = "new"
      page.page_path = ""
      page.save!
    end
    root_webpage.parent = root_webpage
    root_webpage.page_path = "#{"%04d" % id}"
    # Force index page to be rescraped to ensure it is fully spidered.
    root_webpage.status = "unscraped"
    root_webpage.save!

    # Create pages reachable from sitemap.
    spider_sitemap
    save!

    # Scrape pages.
    page_count = 0
    loop do
      unscraped_webpages = Webpage.where(status: "unscraped").order(:id)
      p "!!! Website::scrape unscraped_webpages.count #{unscraped_webpages.count}"
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |page|
        page.scrape(force: force)
        page_count += 1
        return if page_count > page_limit
      end
    end
  end

  def generate_pdf
    p "!!! Website::generate_pdf"
    File.open("/tmp/dh.html", "wb") do |file|
      head = File.read(File.join(Rails.root, 'config', 'website_head.html'))
      file.write("<html>\n#{head}\n<body>\n")
      webpages.reject { |page| page.status != "scraped"}.
        each { |page| page.generate_html(file) }
      browser = Ferrum::Browser.new(
        browser_options: {
          "generate-pdf-document-outline": true
        }
      )
      page = browser.create_page
      page.go_to("file:///tmp/dh.html")
      page.pdf(
        path: "/tmp/dh.pdf",
        landscape: true,
        format: :A4
      )
      file.write("</body>\n</html>\n")
      file.close
      browser.reset
      browser.quit
    end
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

  def url_internal?(url2)
    # p "!!! url #{url} url2 #{url2} #{url2.starts_with?(url)}"
    url2.starts_with?(url)
  end

  private

  def extract_index(root)
    p "!!! Webpage::extract_index root #{root.inspect}"
    document = Nokogiri::HTML(root.content)
    document.css("#main-index li a").map do |entry|
      entry["href"]
    end
  end

  def spider_sitemap
    p "!!! Website::spider_from_sitemap"
    body = Webpage::get_body("#{root_webpage.url}/sitemap")
    document = Nokogiri::HTML(body)
    # Columns of sitemap.
    document.css("#main-content > table > tr > td > table").each do |column|
      p "!!! spidering column #{column.inspect.truncate(400)}"
      spider_sitemap_fragment(root_webpage, column)
    end
  end

  def spider_sitemap_fragment(parent, fragment)
    p ">>>> Website::spider_sitemap_fragment parent.id #{parent.id} fragment #{fragment.text.truncate(200)}"
    fragment.xpath("tr/td").each do |child|
      child.xpath("a").each do |link|
        href = link.attributes["href"].value
        next unless Webpage.local_html?(url, href)
        next if href.ends_with?(".pdf")
        next if href.starts_with?("((")
        webpage = create_webpage(parent, href, status: "unscraped")
        child.xpath("table").each do |table|
          spider_sitemap_fragment(webpage, table)
        end
      end
    end
  end

  def create_webpage(parent, url, status: "new")
    p "!!! create_webpage #{url}"
    Webpage.find_or_initialize_by(url: url) do |page|
      page.website = parent.website
      page.parent = parent
      page.status = status
      page.page_path = "#{parent.page_path}.#{"%04d" % parent.id}"
      page.save!
    end
  end

  def webpage_from_url(webpage_url, force: false)
    webpage = Webpage.find_or_initialize_by(website: self, parent: root_webpage, url: webpage_url) do |page|
      page.status = "unscraped"
    end
    webpage.scrape(force: force, follow_links: false)
  end
end
