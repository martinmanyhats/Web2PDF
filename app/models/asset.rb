class Asset < ApplicationRecord
  has_many :asset_urls

  def self.get_published_assets(website)
    p "!!! get_published_assets"
    assets_regex = Regexp.new("tr class=\"squiz_asset\">#{"<td>([^<]*)</td>" * 5}")
    stream_lines_for_url("#{website.url}/reports/publishedassets").each do |line|
      if line =~ /tr class="squiz_asset"/
        values = line.match(assets_regex)
        # p "!!! values #{values.inspect}"
        Rails.logger.silence do
          asset = Asset.create(assetid: values[1], asset_type: values[2], name: values[3], short_name: values[4])
          JSON.parse(values[5]).map do |url|
            if url.blank?
              case asset.asset_type
              when "MS Word Document"
                url = "#{url}/__data/assets/word_doc/#{squiz_hash(asset.assetid)}{/#{asset.assetid}/#{asset.name}"
              when "MS Excel Document"
                url = "#{url}/__data/assets/excel_doc/#{squiz_hash(asset.assetid)}/#{asset.assetid}/#{asset.name}"
              else
                raise "Website:get_published_assets missing url #{asset.inspect}"
              end
            end
            # Only accumulate URLs for this website.
            asset.asset_urls << AssetUrl.create(url: url) if url.starts_with?(website.hostname)
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

  def page?
    ["Standard Page", "Asset Listing Page"].include? asset_type
  end

  def redirection?
    ["Redirect Page", "DOL Google Sheet viewer"].include? asset_type
  end

  def image?
    ["Image", "Thumbnail"].include? asset_type
  end

  def attachment?
    ["MS Excel Document", "File", "DOL LargeImage", "MS Word Document", "MP3 File", "Video File"].include? asset_type
  end
end
