# frozen_string_literal: true

class VideoFileAsset < DataAsset
  def self.output_dir = "video"
  # def self.toc_name = "Videos"
  def asset_link_type = "extasset"
end
