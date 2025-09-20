class Asset < ApplicationRecord
  belongs_to :website
  has_many :asset_urls

  ASSETID_FORMAT = "%06d".freeze
  SAFE_NAME_REPLACEMENT = "_".freeze

  def self.asset_for_uri(uri) = AssetUrl.find_by(url: "#{uri.host}#{uri.path}")&.asset

  def self.asset_for_url(url) = AssetUrl.find_by(url: url)&.asset

  def self.XXasset_for_redirection(uri)
    p "!!! asset_for_redirection uri #{uri.inspect}"
    response = HTTParty.head(uri, headers: Website.http_headers, follow_redirects: false)
    p "!!! asset_for_redirection response #{response.inspect}"
    if response.code >= 300 && response.code < 400
      location = URI.parse(response["location"])
      asset = asset_for_url("#{location.host}#{location.path}")
      raise "Asset:asset_for_redirection not found uri #{uri}" unless asset
      p "!!! asset #{asset.inspect}"
    else
      raise "Asset:asset_for_redirection not a redirection code #{response.code} uri #{uri}"
    end
    asset
  end

  def self.get_published_assets(website)
    p "!!! get_published_assets"
    assets_regex = Regexp.new("tr class=\"squiz_asset\">#{"<td>([^<]*)</td>" * 5}")
    stream_lines_for_url("#{website.url}/reports/publishedassets").each do |line|
      if line =~ /tr class="squiz_asset"/
        values = line.match(assets_regex)
        # p "!!! values #{values.inspect}"
        # p "!!! assetid #{values[1]}"
        Rails.logger.silence do
          asset = Asset.create(website: website, assetid: values[1], asset_type: values[2], name: values[3], short_name: values[4])
          url_info = JSON.parse(values[5])
          asset_urls = url_info[0].uniq
          if asset_urls.empty?
            case asset.asset_type
            when "MS Word Document"
              url = "#{url}/__data/assets/word_doc/#{asset.squiz_hash}{/#{asset.assetid}/#{asset.name}"
            when "MS Excel Document"
              url = "#{url}/__data/assets/excel_doc/#{asset.squiz_hash}/#{asset.assetid}/#{asset.name}"
            else
              raise "Website:get_published_assets missing url #{asset.inspect}"
            end
          else
            asset_urls.map do |url|
              raise "Asset:get_published_assets duplicate url #{url} assetid #{asset.assetid}" if AssetUrl.where(url: url).exists?
              # Only accumulate URLs for this website.
              # Also suppress bizarro URLs which are likely faulty.
              if url.starts_with?(website.hostname) && !url.include?("/reports/")
                asset.asset_urls << AssetUrl.create(url: url)
              end
            end
          end
          if url_info[1].present?
            asset.redirect_url = url_info[1]
            p "!!! asset.redirect_url #{asset.redirect_url}"
            raise "Asset:get_published_assets missing scheme for redirection #{asset.redirect_url}" unless URI.parse(asset.redirect_url).scheme
            raise "Asset:get_published_assets missing host for redirection #{asset.redirect_url}" unless URI.parse(asset.redirect_url).host
            raise "Asset:get_published_assets missing path for redirection #{asset.redirect_url}" unless URI.parse(asset.redirect_url).path
          end
          p "!!! get_published_assets asset #{asset.inspect} urls #{asset.asset_urls.inspect}"
          asset.save!
        end
      end
    end
  end

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

  def document
    @_document ||=
      begin
        p "!!! document url #{asset_urls.first.url}"
        uri = URI.parse("https://#{asset_urls.first.url}")
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

  def assetid_formatted = ASSETID_FORMAT % assetid

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

  def filename_base = "#{assetid_formatted}-#{name.present? ? "#{safe_name}" : "untitled"}"

  def content_page? = ["Standard Page", "Asset Listing Page", "DOL Google Sheet viewer", "DOL Largeimage"].include? asset_type

  def redirect_page? = ["Redirect Page"].include? asset_type

  def image? = ["Image", "Thumbnail"].include? asset_type

  def pdf? = ["PDF File"].include? asset_type

  def attachment? = ["MS Excel Document", "File", "MS Word Document", "MP3 File", "Video File"].include? asset_type

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
