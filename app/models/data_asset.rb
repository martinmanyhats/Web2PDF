# frozen_string_literal: true
require 'open-uri'

class DataAsset < Asset
  scope :publishable, -> { where(status: "linked") }

  def self.generate(root_dir)
    assets = self.publishable
    p "!!! DataAsset:with_root for #{self.class.name} assets.count #{assets.count}"
    assets.each { it.generate(root_dir) }
    generate_toc(root_dir, assets)
  end

  def generate(root_dir)
    p "!!! DataAsset:with_root assetid #{assetid}"
    filename = filename_from_data_url
    copy_filename = "#{root_dir}/#{output_dir}/#{assetid_formatted}-#{filename}"
    p "!!! DataAsset:with_root url #{url} copy_filename #{copy_filename}"
    IO.copy_stream(URI.open("#{url}"), copy_filename)
  end

  def update_html_link(node)
    self.status = "linked"
    super
  end

  def generated_filename
    "#{website.output_root_dir}/#{output_dir}/#{filename_base}"
  end

  def filename_base
    raise "DataAsset:filename_base name missing" if name.nil?
    "#{assetid_formatted}-#{name.present? ? "#{name}" : "untitled"}"
  end

  private

  def self.generate_toc(root_dir, assets)
    p "!!! generate_toc #{toc_name.downcase} assets.count #{assets.count}"
    toc_basename = "toc-#{toc_name.downcase}"
    toc_filename = "#{root_dir}/html/#{toc_basename}.html"
    website = assets.first.website
    File.open(toc_filename, "w") do |file|
      file.write("<html>\n#{website.html_head(title: toc_name)}\n<h1>Table of #{toc_name}</h1>")
      file.write("<table><thead><th>#{toc_name.singularize}</th><th>Referring pages</th></thead>\n")
      assets.sort_by { it.name.downcase }.each do |asset|
        references = asset.asset_urls.map do |asset_url|
          referring_assets = Link.where(destination: asset).map(&:source).uniq
          referring_assets.map { "<a href='#{it.filename_with_assetid("pdf", "pdf")}'>#{it.title}</a>" }.join(", ")
        end.join("<br />")
        file.write("<tr>")
        file.write("<td><a href='#{root_dir}/#{output_dir}/#{asset.assetid_formatted}-#{asset.name}'>#{asset.name}</a></td>\n")
        file.write("<td>#{references}</td\n")
        file.write("</tr>")
      end
      file.write("</table>\n</html>\n")
      file.close
      Browser.instance.with_root(root_dir) { Browser.instance.html_to_pdf(toc_filename, "#{root_dir}/#{toc_basename}.pdf") }
    end
  end

  def filename_from_data_url
    raise "DataAsset:filename_from_data_url missing asset_url" if asset_urls.empty?
    matches = url.match(%r{__data/assets/\w+/\d+/\d+/(.*)$})
    raise "DataAsset:filename_from_data_url cannot parse url #{url}" if matches.nil?
    matches.captures[0]
  end

  # include/general.inc
  # function get_asset_hash($assetid)
  # {
  #         $assetid = trim($assetid);
  #         do {
  #                 $hash = 0;
  #                 $len = strlen($assetid);
  #                 for ($i = 0; $i < $len; $i++) {
  #                         if ((int) $assetid{$i} != $assetid{$i}) {
  #                                 $hash += ord($assetid{$i});
  #                         } else {
  #                                 $hash += (int) $assetid{$i};
  #                         }
  #                 }
  #                 $assetid = (string) $hash;
  #         } while ($hash > SQ_CONF_NUM_DATA_DIRS);
  #
  #         while (strlen($hash) != 4) {
  #                 $hash = '0'.$hash;
  #         }
  #         return $hash;
  #
  # }
  def squiz_hash
    assetid = assetid.to_s
    loop do
      hash = assetid.each_char.map(&:to_i).sum
      assetid = hash.to_s
      break if hash <= 20 # SQ_CONF_NUM_DATA_DIRS
    end
    "%04d" % assetid
  end
end
