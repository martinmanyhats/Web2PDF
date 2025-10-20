class Asset < ApplicationRecord
  belongs_to :website
  has_many :asset_urls

  ASSETID_FORMAT = "%06d".freeze
  SAFE_NAME_REPLACEMENT = "_".freeze

  HOME_SQUIZ_ASSETID = 93
  SITEMAP_ASSETID = 15632
  PAGE_NOT_FOUND_SQUIZ_ASSETID = 13267
  DVD_README_ASSETID = 19273

  def self.asset_for_uri(uri) = AssetUrl.find_sole_by(url: "#{uri.host}#{uri.path}").asset

  def self.XXasset_for_host_path(host_path) = AssetUrl.find_by(url: host_path).asset

  def self.XXasset_url_for_uri(uri) = AssetUrl.find_sole_by(url: "#{uri.host}#{uri.path}")

  def self.get_published_assets(website)
    # p "!!! get_published_assets"
    assets_regex = Regexp.new("tr class=\"squiz_asset\">#{"<td>([^<]*)</td>" * 5}")
    stream_lines_for_url("#{website.url}/reports/publishedassets").each do |line|
      if line =~ /tr class="squiz_asset"/
        values = line.match(assets_regex)
        # p "!!! values #{values.inspect}"
        assetid = values[1].to_i
        asset_type = values[2]
        asset_class = asset_class_from_asset_type(asset_type)
        Rails.logger.silence do
          asset = asset_class.find_or_create_by!(website: website, assetid: assetid) do |asset|
            asset.asset_type = asset_type
            asset.name = values[3]
            asset.short_name = values[4]
          end
          asset.create_asset_urls(values[5])
          # p "!!! get_published_assets asset #{asset.inspect} urls #{asset.asset_urls.inspect}"
          asset.save!
        end
      end
    end
  end

  def generate(file_root, toc_name)
    p "!!! generate assetid #{assetid}"
    filename = filename_from_data_url
    url = asset_urls.first.url
    copy_filename = "#{file_root}/#{toc_name.downcase}/#{assetid_formatted}-#{filename}"
    IO.copy_stream(URI.open("https://#{url}"), copy_filename)
  end

  def document
    @_document ||=
      begin
        p "!!! document url #{asset_urls.first.url}"
        uri = URI.parse("#{asset_urls.first.url}")
        p "!!! document uri #{uri}"
        response = HTTParty.get(uri, {
          headers: Website.http_headers,
        })
        # TODO: error checking, retry
        # p "!!! Website:content_for_url headers #{response.headers}"
        # p "!!! Website:content_for_url body #{response.body.truncate(8000)}"
        Nokogiri::HTML(response.body)
      end
  end

  def safe_name
    sname = name.present? ? name : short_name
    raise "Asset:safe_name missing name or short_name assetid #{asset.assetid}" if sname.blank?

    sname = sname.downcase
    # Also replace '.' to vaoid suffix confusion.
    sname = sname.gsub(/[^a-z0-9\-]+/, SAFE_NAME_REPLACEMENT)
    sname = sname.gsub(/#{SAFE_NAME_REPLACEMENT}+|#{SAFE_NAME_REPLACEMENT}-#{SAFE_NAME_REPLACEMENT}/, SAFE_NAME_REPLACEMENT)
    sname = sname.gsub(/^#{SAFE_NAME_REPLACEMENT}|#{SAFE_NAME_REPLACEMENT}$/, "")
    if sname.blank?
      return "untitled"
    else
      sname[0, 200]
    end
  end

  def XXurl
    raise "Asset:url missing url" if asset_urls.empty?
    asset_urls.first.url
  end

  def XXwebpages
    asset_urls.map(&:webpage)
  end

  def title
    name.present? ? name : short_name
  end

  def filename_with_assetid(suffix, output_dir = nil)
    output_dir = suffix if output_dir.nil?
    "#{website.output_root}/#{output_dir}/#{filename_base}.#{suffix}"
  end

  def XXbasename_with_assetid
    raise "Asset:basename_with_assetid missing webpage for assetid #{assetid}" if webpage.nil?
    base = webpage.squiz_canonical_url.gsub(/.*\//, "")
    "#{assetid_formatted}-#{base}"
  end

  def assetid_formatted = ASSETID_FORMAT % assetid

  def filename_from_data_url
    raise "Asset:filename_from_data_url missing url" if asset_urls.empty?
    matches = url.match(%r{__data/assets/\w+/\d+/\d+/(.*)$})
    raise "Asset:filename_from_data_url cannot parse url #{url}" if matches.nil?
    matches.captures[0]
  end

  def filename_base = "#{assetid_formatted}-#{name.present? ? "#{safe_name}" : "untitled"}"

  def content? = is_a?(ContentAsset)

  def redirect? = is_a?(RedirectAsset)

  def data? = is_a?(DataAsset)

  def image? = ["Image", "Thumbnail"].include? asset_type

  def pdf? = ["PDF File"].include? asset_type

  def office? = ["MS Excel Document", "MS Word Document"].include? asset_type

  def attachment? = ["File", "MS Excel Document", "MS Word Document", "MP3 File", "Video File"].include? asset_type

  def squiz_canonical_url = asset_urls.first.webpage.squiz_canonical_url

  def home? = assetid == HOME_SQUIZ_ASSETID

  def self.home = Asset.find_sole_by(assetid: HOME_SQUIZ_ASSETID)

  def sitemap? = assetid == SITEMAP_ASSETID

  def page_not_found_? = assetid == PAGE_NOT_FOUND_SQUIZ_ASSETID

  def create_asset_urls(value)
    url_info = JSON.parse(value)
    urls = url_info[0].uniq
    if urls.empty?
      # Some MS assets have no webpath.
      case asset_type
      when "MS Word Document"
        url = "#{website.url}/__data/assets/word_doc/#{squiz_hash}/#{assetid}/#{name}"
      when "MS Excel Document"
        url = "#{website.url}/__data/assets/excel_doc/#{squiz_hash}/#{assetid}/#{name}"
      end
      urls = [url]
    end
    raise "Asset:create_asset_urls no URLs assetid #{assetid}" if urls.empty?
    urls.uniq.map do |url|
      raise "Asset:create_asset_urls duplicate url #{url} assetid #{assetid}" if AssetUrl.where(url: url).exists?
      # Only accumulate URLs for this website.
      if website.internal?(url) && !url.include?("/reports/")
        # p "++++ add asset url #{url}"
        new_asset_url = AssetUrl.find_or_create_by(url: website.normalize(url).to_s)
        asset_urls << new_asset_url if new_asset_url.new_record?
      end
    end
    # Capture any redirection URL.
    self.redirect_url = url_info[1] if url_info[1].present?
  end

  def redirect_url=(url)
    p "!!! redirect_url= #{url}"
    raise "Asset:redirect_url= unexpected redirect URL"
  end

  private

  def self.stream_lines_for_url(url)
    p "!!! stream_lines_for_url #{url}"
    uri = URI(url)
    Enumerator.new do |yielder|
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request) do |response|
          buffer = ""
          response.read_body do |chunk|
            buffer << chunk
            while (line = buffer.slice!(/.*?\n/)) # yield full lines
              line = line.chomp.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
              yielder << line
            end
          end
          # Yield any trailing partial line.
          yielder << buffer unless buffer.empty?
        end
      end
    end
  end

  def self.asset_class_from_asset_type(asset_type)
    case asset_type
    when "Standard Page"
      asset_class = ContentAsset
    when "Asset Listing Page"
      asset_class = ContentAsset
    when "DOL Google Sheet viewer"
      asset_class = ContentAsset
    when "DOL LargeImage"
      asset_class = ContentAsset
    when "File"
      asset_class = DataAsset
    when "Image"
      asset_class = DataAsset
    when "MS Excel Document"
      asset_class = DataAsset
    when "MS Word Document"
      asset_class = DataAsset
    when "PDF File"
      asset_class = DataAsset
    when "Redirect Page"
      asset_class = RedirectAsset
    when "Standard Page"
      asset_class = ContentAsset
    when "Thumbnail"
      asset_class = DataAsset
    when "Video File"
      asset_class = DataAsset
    else
      raise "Website:get_published_assets unknown asset type #{asset_type}"
    end
    asset_class
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
  def squiz_hash
    assetid = assetid.to_s
    loop do
      hash = assetid.each_char.map(&:to_i).sum
      assetid = hash.to_s
      break if hash <= 20 # SQ_CONF_NUM_DATA_DIRS
    end
    "%04d" % assetid
  end

end
