# frozen_string_literal: true

class MsWordDocumentAsset < DataAsset
  def self.output_dir = "file"
  def self.toc_name = "Word files"
end
