# frozen_string_literal: true

class MsExcelDocumentAsset < DataAsset
  def self.output_dir = "file"
  def self.toc_name = "Excel files"

  def self.generate(website, assetids)
    super
  end

  def generate(website)
    p "!!! MsExcelDocumentAsset:generate assetid #{assetid} #{generated_filename}"
    super
    xls_filename = "#{website.output_root_dir}/#{output_dir}/#{assetid_formatted}-#{filename_from_data_url}"
    output_dir = "#{website.output_root_dir}/pdf"
    system("soffice --headless --convert-to pdf --outdir #{output_dir} #{xls_filename}")
  end

  def generated_filename
    "#{website.output_root_dir}/pdf/#{assetid_formatted}-#{name.sub(%r{xlsx?}, "pdf")}"
  end
end
