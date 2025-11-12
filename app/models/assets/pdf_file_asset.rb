# frozen_string_literal: true

class PdfFileAsset < DataAsset
  def self.output_dir = "pdf"
  def self.toc_name = "PDFs"
  def asset_link_type = "extasset"
  def banner_title = "#{short_name} (#{name}) ##{assetid}"
end