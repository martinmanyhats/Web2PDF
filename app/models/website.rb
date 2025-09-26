require 'open-uri'

class Website < ApplicationRecord
  has_many :assets, dependent: :destroy
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  broadcasts_refreshes
  after_update_commit -> { broadcast_refresh_later }

  attr_reader :webroot
  attr_reader :pdf_assets
  attr_reader :office_assets

  DataAsset = Struct.new(:assetid, :short_name, :filename, :url, :digest)

  def spider(options = {})
    p "!!! Website::spider options #{options.inspect} #{inspect}"
    Asset.get_published_assets(self) unless options[:skipassets].present?
    if options[:assetid]
      spider_one(options[:assetid].to_i)
    else
      spider_all(options)
    end
    notify_page_list
  end

  def spider_one(assetid)
    p "!!! spider_one assetid #{assetid}"
    asset = Asset.find_by(assetid: assetid)
    p "!!! spider_one asset #{asset.inspect}"
    webpage = Webpage.find_or_initialize_by(asset: asset) do |page|
      page.website = self
      page.asset_path = "/#{asset.assetid_formatted}"
      page.status = "unspidered"
    end
    webpage.extract_info_from_document
    p "!!! spider_one webpage saving #{webpage.inspect}"
    Rails.logger.silence do
      webpage.save!
    end
    notify_current_webpage(webpage, "spidering")
    webpage.spider(follow_links: false)
  end

  def spider_all(options)
    root_asset = Asset.find_sole_by(assetid: 93)
    self.root_webpage = Webpage.find_or_initialize_by(asset: root_asset) do |page|
      page.website = self
      page.asset_path = "/#{root_asset.assetid_formatted}"
      page.status = "unspidered"
      page.squiz_canonical_url = "#{url}"
    end
    root_webpage.extract_info_from_document
    p "!!! root_webpage saving #{root_webpage.inspect}"
    Rails.logger.silence do
      root_webpage.save!
    end

    spider_unspidered_webpages

    # Add in sitemap after content pages have been spidered. Should be redundant as pages should already have been found.
    spider_sitemap
  end

  def spider_unspidered_webpages
    loop do
      unspidered_webpages = webpages.where(status: "unspidered").order(:id)
      p "!!! Website::spider unspidered_webpages.count #{unspidered_webpages.count}"
      break if unspidered_webpages.empty?
      unspidered_webpages.each do |webpage|
        notify_current_webpage(webpage, "spidering")
        webpage.spider(follow_links: true)
      end
    end
  end

  def generate_archive(options)
    p "!!! Website:generate_archive options #{options.inspect}"
    file_root = "/tmp/dh"
    FileUtils.remove_entry_secure(file_root) if File.exist?(file_root)
    %w[html pdf image assets].each {|subdir| FileUtils.mkdir_p("#{file_root}/#{subdir}")}
    @pdf_assets = Set.new
    @image_assets = Set.new
    @office_assets = Set.new
    if options[:webroot].present?
      @webroot = options[:webroot]
    else
      @webroot = "file://#{file_root}"
    end
    if options[:assetid].present?
      asset = Asset.find_by(assetid: options[:assetid])
      pages = webpages.where(asset_id: asset.id)
    else
      pages = webpages.where(status: "spidered")
    end
    generate_webpages(file_root, pages)
    generate_pdf_assets(file_root, options)
    generate_pdf_toc(file_root, options)
    generate_office_assets(file_root, options)
  end

  def internal?(url_or_uri)
    uri = url_or_uri.kind_of?(String) ? URI.parse(url_or_uri) : url_or_uri
    uri.host == host
  end

  def host
    @_host ||= Addressable::URI.parse(url).host
  end

  def add_pdf(asset)
    p "!!! add_pdf assetid #{asset.assetid}"
    raise "Website:add_pdf no urls" if asset.asset_urls.empty?
    @pdf_assets << asset
  end

  def add_image(asset)
    p "!!! add_image assetid #{asset.assetid}"
    raise "Website:add_image no urls" if asset.asset_urls.empty?
    @image_assets << asset
  end

  def add_office(asset)
    p "!!! add_office assetid #{asset.assetid}"
    raise "Website:add_office no urls" if asset.asset_urls.empty?
    @office_assets << asset
  end

  def generate_webpages(file_root, webpages)
    p "!!! Website:generate_webpages count #{webpages.count}"
    browser = Ferrum::Browser.new(
      browser_options: {
        "generate-pdf-document-outline": true
      }
    )
    webpages.each do |webpage|
      p "========== Website:generate_archive assetid #{webpage.asset.assetid}"
      html_filename = webpage.generate_html(file_root, html_head)
      page = browser.create_page
      page.go_to("file://#{html_filename}")
      page.pdf(
        path: webpage.filename_with_assetid(file_root, "pdf"),
        landscape: true,
        format: :A4
      )
      browser.reset
    end
    browser.quit
  end

  def generate_pdf_assets(file_root, options)
    p "!!! generate_pdf_assets @pdf_assets.count #{@pdf_assets.count}"
    @pdf_assets.each do |asset|
      p "!!! generate_pdf_assets asset #{asset.inspect}"
      filename = asset.filename_from_url
      url = asset.asset_urls.first.url
      # filename = filename_from_url(url, "pdf")
      copy_filename = "#{file_root}/assets/#{asset.assetid_formatted}-#{filename}"
      IO.copy_stream(URI.open("https://#{url}"), copy_filename)
    end
  end

  def generate_pdf_toc(file_root, options)
    p "!!! generate_pdf_toc @pdf_assets.size #{@pdf_assets.size}"
    File.open("#{file_root}/toc-pdfs.html", "w") do |file|
      file.write("<html>\n#{html_head}\n<h1>PDF TOC</h1><table>\n")
      column = 0
      @pdf_assets.sort_by { it.name.downcase }.each do |asset|
        file.write("<tr>") if column % 3 == 0
        file.write("<td><a href='assets/#{asset.assetid_formatted}-#{asset.name}'>#{asset.name}</a></td>\n")
        file.write("</tr>") if (column + 1) % 3 == 0
        column += 1
      end
      file.write("</table>\n</html>\n")
      file.close
    end
  end

  def generate_office_assets(file_root, options)
    p "!!! generate_office_assets @office_assets.count #{@office_assets.count}"
    @office_assets.each do |asset|
      p "!!! generate_office_assets assetid #{asset.assetid} url #{asset.url}"
      basename = File.basename(asset.url)
      pdf_filename = "#{file_root}/assets/#{asset.assetid_formatted}-#{basename}.pdf"
      Libreconv.convert("https://#{asset.url}", pdf_filename)
    end
  end

  def hostname
    @_host ||= Addressable::URI.parse(url).host
  end

  def self.http_headers
    {
      "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
    }
  end

  def log(name, message)
    @logs_created ||= {}
    log_filename = case name
                   when :pdf_duplicates
                     "tmp/pdf_duplicates"
                   when :ignored_links
                     "tmp/ignored_links"
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

  # private

  def filename_from_url(url, suffix)
    matches = url.match(%r{__data/assets/(?:#{suffix})_file/\d+/\d+/(.*\.(?:#{suffix})$)}i)
    raise "Website:filename_from_url cannot parse url #{url} suffix #{suffix}" if matches.nil?
    matches.captures[1]
  end

  def extract_index(root)
    p "!!! Webpage::extract_index root #{root.inspect}"
    document = Nokogiri::HTML(root.content)
    document.css("#main-index li a").map do |entry|
      entry["href"]
    end
  end

  def spider_sitemap
    p "!!! Website::spider_sitemap"
    document = Nokogiri::HTML(URI.open("#{url}/sitemap"))
    document.css("#main-content > table > tr > td > table a").map do |link|
      p "!!! link #{link.inspect}"
      next if link.content.starts_with?("((")
      root_webpage.spider_link(link["href"])
    end
  end

  def XXspider_sitemap_fragment(parent, fragment)
    p ">>>> Website::spider_sitemap_fragment parent.id #{parent.id} fragment #{fragment.text.truncate(200)}"
    fragment.xpath("tr/td").each do |child|
      child.xpath("a").each do |link|
        p "!!! link.content #{link.content}"
        next if link.content.starts_with?("((")
        parent.spider_link(link.attributes["href"].value)
        child.xpath("table").each do |table|
          p "!!! Website::spider_sitemap_fragment descending"
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
    report = Nokogiri::HTML(URI.open("#{url}/reports/allpdfs/_recache"))
    pdfs = report.css("[id='allpdfs'] tr")
    p "!!! get_squiz_pdf_list size #{pdfs.size}"
    pdfs_by_assetid = {}
    pdfs_by_digest = {}
    pdfs.each do |pdf|
      (assetid, short_name, filename, url) = pdf.css("td").map(&:text)
      digest = nil
      p "!!! get_squiz_pdf_list assetid #{assetid} filename #{filename}"
      filename_duplicate = false
      if pdfs_by_assetid.has_key?(assetid)
        existing = pdfs_by_assetid[assetid]
        p ">>> FILENAME assetids #{existing.assetid}:#{assetid} short names #{existing.short_name}:#{short_name} filename #{filename} "
        existing.digest = get_digest(existing.url) unless existing.digest
        digest = get_digest(url)
        filename_duplicate = true
        log(:pdf_duplicates, "FILENAME assetids #{existing.assetid}:#{assetid}   short names #{existing.short_name}:#{short_name}   filename #{filename}  #{digest != existing.digest ? "  CONTENTS DIFFER" : ""}")
        data_asset = existing
      else
        data_asset = DataAsset.new(assetid: assetid.to_i, short_name: short_name, filename: filename, url: url, digest: digest)
        pdfs_by_assetid[filename] = data_asset
      end
      if options.has_key?(:digest)
        digest = get_digest(url) unless digest
        if pdfs_by_digest.has_key?(digest) && !filename_duplicate
          existing = pdfs_by_digest[digest]
          p " >>> CONTENT url #{url} data_asset #{pdfs_by_digest[digest]}"
          log(:pdf_duplicates, "CONTENT assetids #{existing.assetid}:#{assetid}   short names #{existing.short_name}:#{short_name}   filenames #{filename}:#{existing.filename}")
        else
          data_asset.digest = digest
          pdfs_by_digest[digest] = data_asset
        end
      end
    end
    false && @pdf_uris.each do |uri|
      raise "Website:get_squiz_pdf_list unknown filename #{filename}" unless @pdfs_by_filename.has_key?(File.basename(uri.to_s))
    end
    pdfs_by_assetid
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

  def log_to_file(filename, message)
    p "!!! log_to_file #{filename}"
    File.open(filename, "a") { |f| f.puts(message)}
  end
end
