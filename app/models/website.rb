class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  broadcasts_refreshes
  after_update_commit -> { broadcast_refresh_later }

  def scrape(force: false, page_limit: nil)
    p "!!! Website::scrape #{inspect}"
    false && self.root_webpage = Webpage.find_or_initialize_by(squiz_assetid: "93") do |page|
      page.website = self
      page.status = "unscraped"
      page.page_path = ""
      # page.squiz_canonical_url = "https://www.deddingtonhistory.uk/history"
      page.save!
    end
    # root_webpage.parent = root_webpage
    # root_webpage.create_webpage_for_url("https://www.deddingtonhistory.uk/history")
    # root_webpage.save!
    dummy_rootpage = Webpage.new
    dummy_rootpage.website = self
    dummy_rootpage.asset_path = ""
    dummy_rootpage.create_webpage_for_url("https://www.deddingtonhistory.uk/history")

    # Create pages reachable from sitemap.
    # spider_sitemap
    # save!

    # Scrape pages.
    page_count = 0
    loop do
      unscraped_webpages = webpages.where(status: "unscraped").order(:id)
      p "!!! Website::scrape unscraped_webpages.count #{unscraped_webpages.count}"
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |webpage|
        notify_current_webpage(webpage, "scraping") #if page_count % 10 == 0
        webpage.scrape(force: force)
        page_count += 1
        # p ">>> page_limit #{page_limit} page_count #{page_count} if #{page_limit && (page_count > page_limit)}"
        return if page_limit && (page_count > page_limit)
      end
    end
    notify_page_list
  end

  def generate_pdf_files
    p "!!! Website::generate_pdf_files"
    browser = Ferrum::Browser.new(
      browser_options: {
        "generate-pdf-document-outline": true
      }
    )
    head = File.read(File.join(Rails.root, 'config', 'website_head.html'))
    webpages.where(status: "scraped").each do |webpage|
      p "!!! Website::generate_pdf_files assetid #{webpage.squiz_assetid}"
      filename_base = "/tmp/dh/dh-#{"%06d" % webpage.squiz_assetid}"
      File.open("#{filename_base}.html", "wb") do |file|
        file.write("<html>\n#{head}\n<body>\n")
        webpage.generate_html(file)
        file.write("</body>\n</html>\n")
        file.close
        page = browser.create_page
        page.go_to("file://#{filename_base}.html")
        page.pdf(
          path: "#{filename_base}.pdf",
          landscape: true,
          format: :A4
        )
        browser.reset
      end
    end
    browser.quit
  end

  def generate_pdf
    p "!!! Website::generate_pdf"
    File.open("/tmp/dh.html", "wb") do |file|
      head = File.read(File.join(Rails.root, 'config', 'website_head.html'))
      file.write("<html>\n#{head}\n<body>\n")
      webpages.where(status: "scraped").each { |page| page.generate_html(file) }
      file.write("</body>\n</html>\n")
      file.close
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
        format: :A4,
        timeout: 900
      )
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

  def host
    @_host ||= Addressable::URI.parse(url).host
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
      Rails.logger.info "Creating webpage url #{url}"
      Rails.logger.silence do
        page.save!
      end
    end
    notify_current_webpage(webpage, "created")
  end

  def notify_current_webpage(webpage, notice="NONE")
    Turbo::StreamsChannel.broadcast_replace_to(
      "web2pdf",
      target: "website_#{self.id}_current_webpage_info",
      partial: "websites/current_webpage_info",
      locals: {website: self, webpage: webpage, notice: notice}
    )
  end

  def notify_page_list
    Turbo::StreamsChannel.broadcast_replace_to(
      "web2pdf",
      target: "website_#{self.id}_page_list",
      partial: "websites/page_list",
      locals: {website: self}
    )
  end
end
