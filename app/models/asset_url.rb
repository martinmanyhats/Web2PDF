class AssetUrl < ApplicationRecord
  belongs_to :asset

  def self.remap_uri(website, uri)
    @remaps = YAML::load(File.open("#{Rails.root.to_s}/config/asset_url_remaps.yml")) unless @remaps
    # p "!!! remap_uri #{uri}"
    remap_host_path = @remaps["#{uri.host}#{uri.path}"]
    if remap_host_path
      p "!!! remap_uri remapped #{remap_host_path} from #{uri}"
      website.normalize(remap_host_path)
    else
      uri
    end
  end

  def self.remap_and_find_by_uri(website, uri)
    Rails.logger.silence do
      asset_url = AssetUrl.find_by(url: AssetUrl.remap_uri(website, uri).to_s)
      raise "AssetUrl:remap_and_find_by_uri uri not found #{uri}" if asset_url.nil?
      asset_url
    end
  end
end
