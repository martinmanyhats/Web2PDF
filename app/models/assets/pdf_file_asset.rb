# frozen_string_literal: true

class PdfFileAsset < DataAsset
  def self.output_dir = "pdf"
  def self.toc_name = "PDFs"
  def banner_title = "#{short_name} (#{name}) ##{assetid}"
end