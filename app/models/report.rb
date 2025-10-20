# frozen_string_literal: true

class Report
  def self.generate_report(website)
    reports_dir = "#{website.output_root}/reports"
    FileUtils.mkdir_p(reports_dir)

    report_filename = "#{reports_dir}/report-#{DateTime.now.strftime('%Y%m%d')}.xlsx"
    FileUtils.rm(report_filename) if File.exist?(report_filename)
    workbook = FastExcel.open(report_filename, constant_memory: true)
    workbook.default_format.set(
      font_size: 0, # user's default
      font_family: "Arial"
    )

    bold_fmt = workbook.bold_format
    count_fmt = workbook.number_format("#,##0")
    # date_format = workbook.number_format("[$-409]m/d/yy h:mm AM/PM;@")

    summary_sheet = workbook.add_worksheet("Summary")
    summary_sheet.auto_width = true
    summary_sheet.set_column(0, 0, FastExcel::DEF_COL_WIDTH)
    summary_sheet.set_column(1, 1, 20, count_fmt)
    summary_sheet.append_row(["Website", FastExcel::URL.new(website.url)], bold_fmt)
    summary_sheet.append_row([])
    summary_sheet.append_row(["Total assets", website.assets.count], count_fmt)
    summary_sheet.append_row([])
    Asset.group(:asset_type).order(:asset_type).count.each_pair do |key, count|
      summary_sheet.append_row([key, count], count_fmt)
    end

    assets_sheet = workbook.add_worksheet("Assets")
    assets_sheet.auto_width = true
    assets_sheet.append_row(["Name", "Asset #", "Asset type", "URL"], bold_fmt)
    website.assets.order(:id).each do |asset|
      assets_sheet.append_row([asset.short_name, asset.assetid, asset.asset_type, FastExcel::URL.new(asset.canonical_url)])
    end

    workbook.close
  end
end
