class AssetUrl < ApplicationRecord
  belongs_to :asset
  # has_and_belongs_to_many :webpages

  def self.remap_uri(asset, uri)
    @remaps = YAML::load(File.open("#{Rails.root.to_s}/config/asset_url_remaps.yml")) unless @remaps
    # p "!!! remap_uri #{uri}"
    remap_host_path = @remaps["#{uri.host}#{uri.path}"]
    if remap_host_path
      p "!!! remap_uri remapped #{remap_host_path} from #{uri}"
      asset.website.normalize(remap_host_path)
    else
      uri
    end
  end

  def self.remap_and_find_by_uri(asset, uri)
    asset_url = AssetUrl.find_by(url: AssetUrl.remap_uri(asset, uri).to_s)
    raise "AssetUrl:remap_and_find_by_host_path uri not found #{uri} from assetid #{asset.assetid}" if asset_url.nil?
    asset_url
  end
end
