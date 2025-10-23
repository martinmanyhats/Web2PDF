# frozen_string_literal: true

class MsExcelDocumentAsset < DataAsset
  def self.output_dir = "file"
  def self.toc_name = "Excel files"
end
