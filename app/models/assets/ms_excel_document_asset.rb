# frozen_string_literal: true

class MsExcelDocumentAsset < DataAsset
  def self.output_dir = "excel"
  def self.toc_name = "Excel files"
  def asset_link_type = "extasset"

  def generate
    p "!!! MsExcelDocumentAsset:generate assetid #{assetid} #{generated_filename}"
    super
    xls_filename = "#{website.output_root_dir}/assets/#{output_dir}/#{assetid_formatted}-#{filename_from_data_url}"
    outdir = "#{website.output_root_dir}/assets/#{output_dir}"
    # p "!!! MsExcelDocumentAsset:generate xls_filename #{xls_filename} outdir #{outdir}"
    system("soffice --headless --convert-to pdf --outdir #{outdir} #{xls_filename}")
  end

  def generated_filename
    "#{website.output_root_dir}/assets/excel/#{assetid_formatted}-#{name.sub(%r{xlsx?}, "pdf")}"
  end
end
