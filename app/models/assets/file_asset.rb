# frozen_string_literal: true

class FileAsset < DataAsset
  def self.output_dir = "file"
  def self.toc_name = "Files"
  def asset_link_type = "extasset"
end
