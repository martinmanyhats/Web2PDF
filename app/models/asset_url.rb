class AssetUrl < ApplicationRecord
  belongs_to :asset
  has_and_belongs_to_many :webpages

  def self.remap_host_path(host_path)
    @remaps = YAML::load(File.open("#{Rails.root.to_s}/config/asset_url_remaps.yml")) unless @remaps
    # p "!!! remap_host_path #{host_path}"
    remap_host_path = @remaps[host_path]
    if remap_host_path
      # p "!!! remap_host_path remapped #{remap_host_path} from #{host_path}"
      remap_host_path
    else
      host_path
    end
  end

  def self.remap_and_find_by_host_path(host_path)
    asset_url = AssetUrl.find_by(url: AssetUrl.remap_host_path(host_path))
    raise "AssetUrl:remap_and_find_by_host_path host_path not found #{host_path}" if asset_url.nil?
    asset_url
  end
end
