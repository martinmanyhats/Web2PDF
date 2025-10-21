# frozen_string_literal: true
require 'open-uri'

class DataAsset < Asset
  def self.generate(root_dir)
    assets = DataAsset.where(status: "linked")
    p "!!! DataAsset:generate assets.count #{assets.count}"
    assets.each { it.generate(root_dir) }
  end

  def generate(root_dir)
    p "!!! DataAsset:generate assetid #{assetid}"
    filename = filename_from_data_url
    copy_filename = "#{root_dir}/#{output_dir}/#{assetid_formatted}-#{filename}"
    p "!!! DataAsset:generate url #{url} copy_filename #{copy_filename}"
    IO.copy_stream(URI.open("#{url}"), copy_filename)
  end

  def update_html_link(node)
    self.status = "linked"
    super
  end

  private

  def filename_from_data_url
    raise "DataAsset:filename_from_data_url missing asset_url" if asset_urls.empty?
    matches = url.match(%r{__data/assets/\w+/\d+/\d+/(.*)$})
    raise "DataAsset:filename_from_data_url cannot parse url #{url}" if matches.nil?
    matches.captures[0]
  end

  def generated_filename
    "#{website.web_root}/page/#{filename_base}.pdf"
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
