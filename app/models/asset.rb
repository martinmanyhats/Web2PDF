class Asset < ApplicationRecord
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
