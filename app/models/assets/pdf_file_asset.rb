# frozen_string_literal: true

class PdfFileAsset < DataAsset
  def self.output_dir = "pdf"
  def self.toc_name = "PDFs"
end
