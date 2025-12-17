# frozen_string_literal: true
require 'open-uri'

class DataAsset < Asset
  scope :publishable, -> { where(status: "linked") }

  def self.generate(assets)
    super
    generate_toc(assets)
  end

  def generate
    "!!! DataAsset:generate assetid #{assetid}"
    copy_filename = "#{website.output_root_dir}/#{output_dir}/#{assetid_formatted}-#{filename_from_data_url}"
    p "!!! DataAsset:generate url #{url} copy_filename #{copy_filename}"
    IO.copy_stream(URI.open("#{url}"), copy_filename)
    copy_filename
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
    "#{assetid_formatted}-#{name}"
  end

  def self.generate_toc(assets)
    p "!!! generate_toc #{toc_name} assets.count #{assets.count}"
    return if assets.empty?
    website = assets.first.website
    File.open(toc_filename(website), "w") do |file|
      home_link = "<span class='w2p-breadcrumb'><a href='intasset://#{ContentAsset.home.assetid}:0'>#{ContentAsset.home.short_name}</a></span>"
      title = "<div class='w2p-header'><span class='w2p-title'>Table of #{toc_name}</span><span class='w2p-breadcrumbs'>#{home_link}</span></div>"
      file.write("<html>\n#{website.html_head(toc_name)}\n#{title}\n")
      file.write("<table class='w2p-toc'><thead><th>#{toc_name.singularize}</th><th>Referring pages</th></thead>\n")
      assets.sort_by { it.name.downcase }.each do |asset|
        references = asset.asset_urls.map do |asset_url|
          referring_assets = Link.where(destination: asset).map(&:source).uniq
          referring_assets.map do |referring_asset|
            raise "DataAsset:generate_toc referring asset not ContentAsset assetid #{referring_asset.assetid}" unless referring_asset.is_a?(ContentAsset)
            "<a href='intasset://#{referring_asset.assetid}:0'>#{referring_asset.title}</a>"
          end.join("<br />")
        end.join("<br />")
        file.write("<tr>")
        # file.write("<td><a href='#{website.output_root_dir}/#{output_dir}/#{asset.assetid_formatted}-#{asset.name}'>#{asset.name}</a></td>\n")
        file.write("<td>#{asset.name} [##{asset.assetid}]</td>\n")
        file.write("<td>#{references}</td\n")
        file.write("</tr>")
      end
      file.write("</table>\n</html>\n")
      file.close
      Browser.instance.session { Browser.instance.html_to_pdf(toc_filename(website), toc_pdf_filename(website)) }
      pdf_relative_links(website, toc_pdf_filename(website))
    end
  end

  def self.toc_filename(website) = "#{website.output_root_dir}/#{WORKING_DIR}/html/#{toc_basename}.html"

  def self.toc_pdf_filename(website) = "#{website.output_root_dir}/#{WORKING_DIR}/#{toc_basename}.pdf"

  def self.toc_basename = "toc-#{toc_name.downcase.gsub(/ /, "_")}"

  def self.toc_destination_name = "w2p-destination-#{toc_basename}"

  private

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
