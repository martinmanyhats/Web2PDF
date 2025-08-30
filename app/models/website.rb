require 'open-uri'

class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  broadcasts_refreshes
  after_update_commit -> { broadcast_refresh_later }

  attr_reader :webroot

  def scrape(options)
    p "!!! Website::scrape options #{options.inspect} #{inspect}"
    if options[:assetid]
      scrape_one(options[:assetid].to_i)
    else
      scrape_all
    end
    notify_page_list
  end

  def scrape_one(assetid)
    p "!!! scrape_one assetid #{assetid}"
    webpage = webpages.find_sole_by(squiz_assetid: assetid)
    raise "Website:scrape_one assetid not found #{assetid}" unless webpage
    notify_current_webpage(webpage, "scraping")
    webpage.status = "unscraped"
    webpage.scrape(follow_links: false)
  end

  def scrape_all
    self.root_webpage = Webpage.find_or_initialize_by(squiz_assetid: "93") do |page|
      page.website = self
      page.page_path = ""
      page.status = "unscraped"
    end
    root_webpage.extract_squiz
    root_webpage.save!

    # Create pages reachable from sitemap.
    # spider_sitemap

    # Loop until all pages are scraped.
    page_count = 0
    loop do
      unscraped_webpages = webpages.where(status: "unscraped").order(:id)
      p "!!! Website::scrape unscraped_webpages.count #{unscraped_webpages.count}"
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |webpage|
        notify_current_webpage(webpage, "scraping")
        webpage.scrape(follow_links: true)
        page_count += 1
        # p ">>> page_limit #{page_limit} page_count #{page_count} if #{page_limit && (page_count > page_limit)}"
        return if page_limit && (page_count > page_limit)
      end
    end
  end

  def generate_pdf_files(options)
    p "!!! Website:generate_pdf_files options #{options.inspect}"
    FileUtils.mkdir_p("/tmp/dh")
    browser = Ferrum::Browser.new(
      browser_options: {
        "generate-pdf-document-outline": true
      }
    )
    if options[:webroot].present?
      @webroot = options[:webroot]
    else
      @webroot = "file:///tmp/dh"
    end
    if options[:assetid].present?
      pages = webpages.where(squiz_assetid: options[:assetid])
    else
      pages = webpages.where(status: "scraped")
    end
    p "!!! Website:generate_pdf_files count #{pages.count}"
    @pdf_assets = []
    pages.each do |webpage|
      p "========== Website:generate_pdf_files assetid #{webpage.squiz_assetid}"
      html_filename = webpage.generate_html(html_head)
      page = browser.create_page
      page.go_to("file://#{html_filename}")
      page.pdf(
        path: webpage.generated_filename("pdf"),
        landscape: true,
        format: :A4
      )
      browser.reset
    end
    browser.quit
    generate_pdf_assets(options)
    generate_pdf_toc(options)
  end

  def XXgenerate_pdfs
    scraped_pages = Webpage.where(status: "scraped")
    root_pdf_filename = root_webpage.generate_pdf
    pdf_filenames = scraped_pages.map do |page|
      page.generate_pdf unless page == root_webpage
    end.compact
    pdf_filenames.insert(0, root_pdf_filename)
    p "!!! pdf_filenames #{pdf_filenames.inspect}"
    pdf_filenames
  end

  def XXgenerate_pdf
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

  def url_internal?(url2)
    # p "!!! url #{url} url2 #{url2} #{url2.starts_with?(url)}"
    url2.starts_with?(url)
  end

  def host
    @_host ||= Addressable::URI.parse(url).host
  end

  def add_pdf_asset(uri)
    p "!!! add_pdf_asset uri #{uri}"
    @pdf_assets << uri
  end

  def generate_pdf_assets(options)
    p "!!! @pdf_assets.count #{@pdf_assets.count}"
    @pdf_assets.each do |uri|
      p "!!! generate_pdf_asset uri #{uri}"
      (pdf_assetid, pdf_filename) = uri.to_s.match(%r{__data/assets/pdf_file/\d+/(\d+)/(.*\.pdf$)}).captures
      raise "Website:generate_pdf_assets cannot parse uri #{uri}" if pdf_assetid.nil? || pdf_filename.nil?
      filename = "/tmp/dh/pdf-#{"%06d" % pdf_assetid}-#{pdf_filename}"
      IO.copy_stream(URI.open(uri), filename)
    end
  end

  def generate_pdf_toc(options)
    p "!!! generate_pdf_toc"
    File.open("/tmp/dh/toc-pdfs.html", "w") do |file|
      file.write("<html>\n#{html_head}\n<body>\n<ul>\n")
      @pdf_assets.each do |uri|
        file.write("<li><a href='#{uri}'>#{uri}</a></li>\n")
      end
      file.write("</ul>\n</body>\n</html>\n")
      file.close
    end
  end

  def body(a_url)
    p "!!! Website:body url #{a_url}"
    response = HTTParty.get(a_url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    # TODO: error checking, retry
    p "!!! Website:body headers #{response.headers}"
    response.body
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

  def html_head
    @_html_head ||= File.read(File.join(Rails.root, 'config', 'website_head.html'))
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
