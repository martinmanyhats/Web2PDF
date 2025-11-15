# frozen_string_literal: true

class Website < ApplicationRecord
  has_many :assets, dependent: :destroy

  broadcasts_refreshes
  after_update_commit -> { broadcast_refresh_later }

  # FileAsset = Struct.new(:assetid, :short_name, :filename, :url, :digest)

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
    [ContentAsset.introduction, ContentAsset.home].each do|asset|
      asset.status = "unspidered"
      asset.save!
    end

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
        content_assets = ContentAsset.where(assetid: assetids)
        pdf_file_assets = PdfFileAsset.where(assetid: assetids)
        image_assets = ImageAsset.where(assetid: assetids)
        file_assets = FileAsset.where(assetid: assetids)
        excel_assets = MsExcelDocumentAsset.where(assetid: assetids)
      else
        content_assets = ContentAsset.sitemap_ordered
        pdf_file_assets = PdfFileAsset.publishable
        image_assets = ImageAsset.publishable
        file_assets = FileAsset.publishable
        excel_assets = MsExcelDocumentAsset.publishable
        not_ordered = ContentAsset.publishable - content_assets
        not_ordered.each { p ">>> generate_archive not_ordered #{it.assetid} #{it.short_name}" }
        raise "Website:generate_archive assets missing from sitemap" unless not_ordered.empty?
      end

      Browser.instance.session do
        ContentAsset.generate(content_assets)
      end
      unless options[:contentonly]
        PdfFileAsset.generate(pdf_file_assets)
        ImageAsset.generate(image_assets)
        FileAsset.generate(file_assets)
        MsExcelDocumentAsset.generate(excel_assets)
      end
    end
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
    dirs = %w(excel files image pdf).map { "assets/#{it}" }.join(" ")
    p "!!! dirs #{dirs}"
    zip_filename = "/tmp/dh-#{DateTime.now.strftime('%Y%m%d')}.zip"
    File.delete(zip_filename) if File.exist?(zip_filename)
    system("cd #{output_root_dir} && zip -r #{zip_filename} DeddingtonHistory-*.pdf #{dirs}")
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
