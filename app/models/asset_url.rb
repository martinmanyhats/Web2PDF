class AssetUrl < ApplicationRecord
  belongs_to :asset
  belongs_to :webpage, optional: true

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
end
