class Website < ApplicationRecord
  has_many :assets, dependent: :destroy

  broadcasts_refreshes
  after_update_commit -> { broadcast_refresh_later }

  # attr_reader :web_root

  FileAsset = Struct.new(:assetid, :short_name, :filename, :url, :digest)

  def spider(options = {})
    p "!!! Website::spider options #{options.inspect} #{inspect}"
    Asset.get_published_assets(self) unless options[:skipassets].present?
    notify_page_list
    spider_content(options)
    notify_page_list
    Report::generate_report(self)
  end

  def spider_content(options = {})
    p "!!! spider_content options #{options.inspect} #{inspect}"
    home_asset = Asset.home
    home_asset.status = "unspidered"
    home_asset.save!

    spider = Spider.new(self)
    loop do
      unspidered_assets = Asset.where(status: "unspidered").order(:id)
      p "!!! Website::spider_content unspidered_assets.count #{unspidered_assets.count}"
      break if unspidered_assets.empty?
      unspidered_assets.each do |asset|
        notify_current_asset(asset, "spidering")
        spider.spider_asset(asset)
      end
    end
    notify_current_asset(nil, "spider complete")
  end

  def generate_archive(options)
    Rails.logger.silence do
      p "!!! Website:generate_archive options #{options.inspect}"
      FileUtils.remove_entry_secure(output_root_dir) if File.exist?(output_root_dir)
      Asset.create_dirs(output_root_dir)
      if options[:assetids].present?
        assetids = options[:assetids].split(",").map(&:to_i)
      else
        assetids = nil
      end
      p "!!! Website:generate_archive assetids #{assetids.inspect}"
      Browser.instance.session do
        generate_readme
        ContentAsset.generate(assetids: assetids)
      end
      unless options[:contentonly]
        PdfFileAsset.generate(self)
        ImageAsset.generate(self)
        MsExcelDocumentAsset.generate(self)
        MsWordDocumentAsset.generate(self)
      end
    end
    if options[:combine_pdf]
      PDF.combine_pdfs
    end
  end

  def generate_readme
    readme = Asset.find_sole_by(assetid: Asset::DVD_README_ASSETID)
    readme.extract_content_info
    html_filename = "#{output_root_dir}/html/readme.html"
    pdf_filename = "#{output_root_dir}/readme.pdf"
    readme.generate(html_filename: html_filename, pdf_filename: pdf_filename)
  end

  def internal?(url_or_uri)
    if url_or_uri.kind_of?(String)
      url_or_uri = "https://#{url_or_uri}" unless url_or_uri =~ /^https?:\/\//
      url_or_uri = URI.parse(url_or_uri)
    end
    url_or_uri.host == host
  end

  def host
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
    File.open(log_filename, "a") { |file| file.puts(message) }
  end

  def normalize(url_or_uri)
    # p "!!! normalize #{url_or_uri.inspect}"
    uri = if url_or_uri.kind_of?(String)
            url_or_uri = url_or_uri.strip
            url_or_uri = "https://#{url_or_uri}" unless url_or_uri =~ /^https?:\/\//
            Addressable::URI.parse(url_or_uri)
          else
            url_or_uri
          end
    return uri if uri.scheme == "mailto"
    if uri.scheme.blank?
      uri.scheme = "https"
    end
    if uri.host.blank?
      uri.host = website_host
    end
    if uri.host == website_host
      if uri.scheme == "http"
        uri.scheme = "https"
      end
      if uri.path.ends_with?("/")
        uri.path = uri.path.chop
      end
    end
    uri.fragment = nil
    uri.query = nil
    # p "!!! normalize result #{uri.inspect}"
    uri
  end

  def website_host
    @website_host ||= Addressable::URI.parse(url).host
  end

  def fetch_head_for_uri(uri, limit = 5)
    p "!!! fetch_head_for_uri uri #{uri}"
    raise "Website:fetch_head_for_uri redirected too many times" if limit == 0
    response = nil
    Net::HTTP.start(uri.host, uri.port) do
      it.open_timeout = 10
      it.read_timeout = 10
      p "!!! request_head uri #{uri.to_s}"
      response = it.request_head(uri.to_s)
    end
    p "!!! fetch_head_for_uri response #{response}"
    case response
    when Net::HTTPSuccess then
      p "**** SUCCESS"
      return [uri, response.content_type]
    when Net::HTTPRedirection then
      p "**** REDIRECTION to #{response['location']}"
      return fetch_head_for_uri(URI.parse(response['location']), limit - 1)
    when nil
      raise "Website:fetch_head_for_uri nil"
    end
    raise "Website:fetch_head_for_uri unexpected HTTP code #{response.code}"
  end

  def html_head(title)
    ApplicationController.renderer.render(
      template: "websites/website_head",
      locals: { website: self, title: title ? "#{title} - " : "" },
      layout: false
    )
  end

  def zip_archive
    dirs = Asset.output_dirs.join(" ")
    zip_filename = "/tmp/dh-#{DateTime.now.strftime('%Y%m%d')}.zip"
    File.delete(zip_filename) if File.exist?(zip_filename)
    system("cd #{output_root_dir} && zip -r #{zip_filename} *.pdf #{dirs}")
    zip_filename
  end

  private

  def canonical_url_for_url(url)
    uri = normalize(url)
    return url if uri.host != host
    # p "!!! canonical_url_for_url #{url} uri #{uri}"
    # Some redirected links are direct to a PDF.
    return url if uri.path.match?(/.pdf$/i)
    asset = Asset.asset_for_uri(self, uri)
    if asset.is_a?(ContentAsset)
      asset.canonical_url
    elsif asset.is_a?(RedirectPageAsset)
      p "!!! canonical_url_for_url redirecting to #{asset.redirect_url}"
      canonical_url_for_url(asset.redirect_url)
    else
      url
    end
  end

=begin
  def get_squiz_pdf_list(options)
    p "!!! get_squiz_pdf_list otions #{options.inspect}"
    report = Nokogiri::HTML(URI.open("#{url}/reports/allpdfs"))
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
        data_asset = FileAsset.new(assetid: assetid.to_i, short_name: short_name, filename: filename, url: url, digest: digest)
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
=end

  def notify_current_asset(asset, notice = "NONE")
    Turbo::StreamsChannel.broadcast_replace_to(
      "web2pdf",
      target: "website_#{self.id}_current_asset_info",
      partial: "websites/current_asset_info",
      locals: { website: self, asset: asset, notice: notice }
    )
  end

  def notify_page_list
    Turbo::StreamsChannel.broadcast_replace_to(
      "web2pdf",
      target: "website_#{self.id}_page_list",
      partial: "websites/page_list",
      locals: { website: self }
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
    File.open(filename, "a") { |f| f.puts(message) }
  end
end
