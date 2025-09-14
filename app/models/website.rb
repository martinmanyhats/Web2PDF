class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  broadcasts_refreshes
  after_update_commit -> { broadcast_refresh_later }

  attr_reader :webroot
  attr_reader :pdfs_by_filename

  DataAsset = Struct.new(:assetid, :short_name, :filename, :url, :digest)

  def scrape(options = {})
    p "!!! Website::spider options #{options.inspect} #{inspect}"
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
    notify_current_webpage(webpage, "scraping")
    webpage.status = "unscraped"
    webpage.spider(follow_links: false)
  end

  def scrape_all
    self.root_webpage = Webpage.find_or_initialize_by(squiz_assetid: "93") do |page|
      page.website = self
      page.asset_path = ""
      page.status = "unscraped"
      page.squiz_canonical_url = "#{url}"
      p "!!! page #{page.inspect}"
    end
    p "!!! root_webpage #{root_webpage.inspect}"
    root_webpage.extract_info_from_document
    root_webpage.save!

    # Create pages reachable from sitemap.
    # spider_sitemap

    # Loop until all pages are scraped.
    page_count = 0
    loop do
      unscraped_webpages = webpages.where(status: "unscraped").order(:id)
      p "!!! Website::spider unscraped_webpages.count #{unscraped_webpages.count}"
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |webpage|
        notify_current_webpage(webpage, "scraping")
        webpage.spider(follow_links: true)
        page_count += 1
        # p ">>> page_limit #{page_limit} page_count #{page_count} if #{page_limit && (page_count > page_limit)}"
        # return if page_limit && (page_count > page_limit)
      end
    end
  end

  class XXPublishedAssetsDocument < Nokogiri::XML::SAX::Document
    def start_element(name, attrs = [])
      p "!!! start_element #{name}"
    end

    def end_element(name)
      p "!!! end_element #{name}"
    end
  end

  def extract(options = {})
    p "!!! Website::extract options #{options.inspect} #{inspect}"
    Asset.get_published_assets(self) unless options[:skiplist].present?
    p "!!! assets.count #{Asset.count}"

    if options[:assetid]
      extract_one(options[:assetid].to_i)
    else
      extract_all
    end
    notify_page_list
  end

  def extract_one(assetid)
    p "!!! extract_one assetid #{assetid}"
    webpage = webpages.find_sole_by(squiz_assetid: assetid)
    notify_current_webpage(webpage, "scraping")
    webpage.status = "unscraped"
    webpage.spider(follow_links: false)
  end

  def extract_all
    self.root_webpage = Webpage.find_or_initialize_by(squiz_assetid: "93") do |page|
      page.website = self
      page.asset_path = "/"
      page.status = "unscraped"
      page.squiz_canonical_url = "#{url}"
      p "!!! page #{page.inspect}"
    end
    p "!!! root_webpage #{root_webpage.inspect}"
    root_webpage.extract_info_from_document(root_webpage.document_for_url(url))
    root_webpage.save!

    # Create pages reachable from sitemap.
    # spider_sitemap

    # Loop until all pages are scraped.
    page_count = 0
    loop do
      unscraped_webpages = webpages.where(status: "unscraped").order(:id)
      p "!!! Website::spider unscraped_webpages.count #{unscraped_webpages.count}"
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |webpage|
        notify_current_webpage(webpage, "scraping")
        webpage.spider(follow_links: true)
        page_count += 1
        # p ">>> page_limit #{page_limit} page_count #{page_count} if #{page_limit && (page_count > page_limit)}"
        # return if page_limit && (page_count > page_limit)
      end
    end
    notify_current_webpage(nil, "scrape complete")
  end

  def generate_pdf_files(options)
    @pdf_uris = Set.new
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
    @pdf_uris = []
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
      file.write("<html>\n#{head}\n<content_for_url>\n")
      webpages.where(status: "scraped").each { |page| page.generate_html(file) }
      file.write("</content_for_url>\n</html>\n")
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

  def add_pdf_uri(uri)
    p "!!! add_pdf_uri uri #{uri}"
    raise "Website:add_pdf_uri blank" if uri.blank?
    # parse_data_asset_uri(uri, "pdf")
    @pdf_uris << uri
    p "!!! add_pdf_uri @pdf_uris.size #{@pdf_uris.size}"
  end

  def generate_pdf_assets(options)
    require 'open-uri'
    p "!!! @pdf_uris.count #{@pdf_uris.count}"
    @pdf_uris.each do |uri|
      p "!!! generate_pdf_asset uri #{uri}"
      (pdf_assetid, pdf_filename) = parse_data_asset_uri(uri, "pdf")
      filename = "/tmp/dh/pdf-#{"%06d" % pdf_assetid}-#{pdf_filename}"
      IO.copy_stream(URI.open(uri), filename)
    end
  end

  def generate_pdf_toc(options)
    p "!!! generate_pdf_toc @pdf_uris.size #{@pdf_uris.size}"
    get_squiz_pdf_list(options)
    p "!!! generate_pdf_toc @pdfs_by_filename.size #{@pdfs_by_filename.size}"
    File.open("/tmp/dh/toc-pdfs.html", "w") do |file|
      file.write("<html>\n#{html_head}\n<h1>PDF TOC</h1><table>\n")
      @pdfs_by_filename.each_key.sort do |filename|
        file.write("<tr><td><a href='#{filename}'>#{filename}</a></td></tr>\n")
      end
      file.write("</table>\n</html>\n")
      file.close
    end
  end

  def content_for_url(a_url)
    # p "!!! Website:content_for_url url #{a_url}"
    response = HTTParty.get(a_url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    # TODO: error checking, retry
    # p "!!! Website:content_for_url headers #{response.headers}"
    # p "!!! Website:content_for_url body #{response.body.truncate(8000)}"
    response.body
  end

  def hostname
    @_host ||= Addressable::URI.parse(url).host
  end

  private

  def parse_data_asset_uri(uri, suffix)
    matches = uri.to_s.match(%r{__data/assets/#{suffix}_file/\d+/(\d+)/(.*\.#{suffix}$)})
    raise "Website:parse_data_asset_uri cannot parse uri #{uri} suffix #{suffix}" if matches.nil?
    matches.captures
  end

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

  def get_squiz_pdf_list(options)
    p "!!! get_squiz_pdf_list otions #{options.inspect}"
    report = Nokogiri::HTML(URI.open("#{url}/reports/allpdfs"))
    pdfs = report.css("[id='allpdfs'] tr")
    p "!!! get_squiz_pdf_list size #{pdfs.size}"
    @pdfs_by_filename = {}
    @pdfs_by_digest = {}
    pdfs.each do |pdf|
      (assetid, short_name, filename, url) = pdf.css("td").map(&:text)
      digest = nil
      p "!!! get_squiz_pdf_list assetid #{assetid} filename #{filename}"
      filename_duplicate = false
      if @pdfs_by_filename.has_key?(filename)
        existing = @pdfs_by_filename[filename]
        p ">>> FILENAME assetids #{existing.assetid}:#{assetid} short names #{existing.short_name}:#{short_name} filename #{filename} "
        existing.digest = get_digest(existing.url) unless existing.digest
        digest = get_digest(url)
        filename_duplicate = true
        log(:pdf_duplicates, "FILENAME assetids #{existing.assetid}:#{assetid}   short names #{existing.short_name}:#{short_name}   filename #{filename}  #{digest != existing.digest ? "  CONTENTS DIFFER" : ""}")
        asset = existing
      else
        asset = DataAsset.new(assetid: assetid.to_i, short_name: short_name, filename: filename, url: url, digest: digest)
        @pdfs_by_filename[filename] = asset
      end
      if options.has_key?(:digest)
        digest = get_digest(url) unless digest
        if @pdfs_by_digest.has_key?(digest) && !filename_duplicate
          existing = @pdfs_by_digest[digest]
          p " >>> CONTENT url #{url} asset #{@pdfs_by_digest[digest]}"
          log(:pdf_duplicates, "CONTENT assetids #{existing.assetid}:#{assetid}   short names #{existing.short_name}:#{short_name}   filenames #{filename}:#{existing.filename}")
        else
          asset.digest = digest
          @pdfs_by_digest[digest] = asset
        end
      end
    end
    @pdf_uris.each do |uri|
      raise "Website:get_squiz_pdf_list unknown filename #{filename}" unless @pdfs_by_filename.has_key?(File.basename(uri.to_s))
    end
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

  def get_digest(url)
    require "digest"
    if url.blank?
      digest = "0000000000000000"
    else
      pdf_content = Net::HTTP.get(URI.parse(url))
      digest = Digest::MD5.hexdigest(pdf_content)
    end
    digest
  end

  def log(name, message)
    @logs_created ||= {}
    log_filename = case name
                   when :pdf_duplicates
                     "tmp/pdf_duplicates"
                   else
                     raise "Website:log unknown name #{name}"
                   end
    p "!!! log #{log_filename} @log_created.has_key?(log_filename) #{@logs_created.has_key?(log_filename)}"
    unless @logs_created.has_key?(log_filename)
      File.open(log_filename, "w") do |file|
        p "!!! Website:log created #{log_filename}"
        file.puts("Log created #{DateTime.now.iso8601}")
        @logs_created[log_filename] = true
      end
    end
    File.open(log_filename, "a") { |file| file.puts(message)}
  end

  def log_to_file(filename, message)
    p "!!! log_to_file #{filename}"
    File.open(filename, "a") { |f| f.puts(message)}
  end

  # include/general.inc
  # function get_asset_hash($assetid)
  # {
  #         $assetid = trim($assetid);
  #         do {
  #                 $hash = 0;
  #                 $len = strlen($assetid);
  #                 for ($i = 0; $i < $len; $i++) {
  #                         if ((int) $assetid{$i} != $assetid{$i}) {
  #                                 $hash += ord($assetid{$i});
  #                         } else {
  #                                 $hash += (int) $assetid{$i};
  #                         }
  #                 }
  #                 $assetid = (string) $hash;
  #         } while ($hash > SQ_CONF_NUM_DATA_DIRS);
  #
  #         while (strlen($hash) != 4) {
  #                 $hash = '0'.$hash;
  #         }
  #         return $hash;
  #
  # }
  def squiz_hash(assetid)
    p "!!! squiz_hash assetid #{assetid}"
    assetid = assetid.to_s
    loop do
      hash = assetid.each_char.map(&:to_i).sum
      assetid = hash.to_s
      break if hash <= 20 # SQ_CONF_NUM_DATA_DIRS
    end
    "%04d" % assetid
  end
end
