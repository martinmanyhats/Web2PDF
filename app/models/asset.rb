# frozen_string_literal: true

class Asset < ApplicationRecord
  belongs_to :website
  has_many :asset_urls
  has_many :links, dependent: :destroy, foreign_key: "source_id"

  ASSETID_FORMAT = "%05d".freeze
  SAFE_NAME_REPLACEMENT = "_".freeze

  def output_dir = self.class.output_dir

  def self.generate(assets)
    assets.each { it.generate }
  end

  def self.asset_for_uri(website, uri)
    return nil if uri.nil?
    uri = website.normalize(uri) # Will also convert String to URI.
    if uri.host != website.host ||
       uri.path.blank? ||
       !(uri.scheme == "http" || uri.scheme == "https") ||
       uri.path.match?(%r{/(mainmenu|reports|testing)})
      p "!!! Asset:asset_for_uri skipping #{uri}"
      return nil
    end
    AssetUrl.remap_and_find_by_uri(website, uri)&.asset
  end

  def self.get_published_assets(website)
    p "!!! get_published_assets website #{website.inspect}"
    assets_regex = Regexp.new("tr class=\"squiz_asset\">#{"<td>([^<]*)</td>" * 5}")
    stream_lines_for_url("#{website.url}/reports/publishedassets").each do |line|
      if line =~ /tr class="squiz_asset"/
        values = line.match(assets_regex)
        # p "!!! values #{values.inspect}"
        assetid = values[1].to_i
        asset_type = values[2]
        asset_class = asset_class_from_asset_type(asset_type)
        Rails.logger.silence do
          asset = asset_class.find_or_create_by!(website: website, assetid: assetid) do |asset|
            asset.asset_type = asset_type
            asset.name = values[3]
            asset.short_name = values[4]
          end
          asset.create_asset_urls(values[5])
          # p "!!! get_published_assets asset #{asset.inspect} urls #{asset.asset_urls.inspect}"
          asset.save!
        end
      end
    end
    p "!!! get_published_assets count #{Asset.count}"
  end

  def self.asset_class_from_asset_type(asset_type)
    %w{PDF DOL MS}.each { asset_type = asset_type.sub(it, it.capitalize) }
    klass_name = "#{asset_type.gsub(" ", "")}Asset"
    klass = klass_name.constantize
    raise "Asset:asset_class_from_asset_type no matching class #{asset_type}" if klass.nil?
    klass
  end

  def parents
    Link.where(destination: self).map(&:source)
  end

  def safe_name
    sname = name.present? ? name : short_name
    raise "Asset:safe_name missing name or short_name assetid #{asset.assetid}" if sname.blank?

    sname = sname.downcase
    sname = sname.gsub("&amp;", "_and_")
    sname = sname.gsub(/[^a-z0-9\-]+/, SAFE_NAME_REPLACEMENT)
    sname = sname.gsub(/#{SAFE_NAME_REPLACEMENT}+|#{SAFE_NAME_REPLACEMENT}-#{SAFE_NAME_REPLACEMENT}/, SAFE_NAME_REPLACEMENT)
    sname = sname.gsub(/^#{SAFE_NAME_REPLACEMENT}|#{SAFE_NAME_REPLACEMENT}$/, "")
    if sname.blank?
      return "untitled"
    else
      sname[0, 200]
    end
  end

  def clean_short_name
    short_name.gsub("&amp;", "&")
  end

  def banner_title = clean_short_name

  def title
    name.present? ? name : short_name
  end

  def filename_with_assetid(suffix, subdir = nil)
    raise "Asset:filename_with_assetid website.output_root_dir nil" if website.output_root_dir.nil?
    subdir.nil? ? subdir = "assets/#{output_dir}" : ""
    "#{website.output_root_dir}/#{subdir}/#{filename_base}.#{suffix}"
  end

  def assetid_formatted = ASSETID_FORMAT % assetid

  def url
    raise "Asset:url no asset_urls" if asset_urls.empty?
    url = asset_urls.first.url
    raise "Asset:url no url" if url.nil?
    url
  end

  def add_footer? = false

  def create_asset_urls(value)
    url_info = JSON.parse(value)
    urls = url_info[0].uniq
    if urls.empty?
      # Some MS assets have no webpath.
      case asset_type
      when "MS Word Document"
        url = "#{website.url}/__data/assets/word_doc/#{squiz_hash}/#{assetid}/#{name}"
      when "MS Excel Document"
        url = "#{website.url}/__data/assets/excel_doc/#{squiz_hash}/#{assetid}/#{name}"
      end
      urls = [url]
    end
    raise "Asset:create_asset_urls no URLs assetid #{assetid}" if urls.empty?
    urls.uniq.map do |url|
      raise "Asset:create_asset_urls duplicate url #{url} assetid #{assetid}" if AssetUrl.where(url: url).exists?
      # Only accumulate URLs for this website.
      if website.internal?(url) && !url.include?("/reports/")
        # p "++++ add asset url #{url}"
        new_asset_url = AssetUrl.find_or_create_by(url: website.normalize(url).to_s)
        asset_urls << new_asset_url if new_asset_url.new_record?
      end
    end
    # Capture any redirection URL.
    self.redirect_url = url_info[1] if url_info[1].present?
  end

  def redirect_url=(url)
    p "!!! redirect_url= #{url}"
    raise "Asset:redirect_url= unexpected redirect URL"
  end

  def self.create_dirs(root_dir)
    output_dirs.each { FileUtils.mkdir_p("#{root_dir}/assets/#{it}") }
    FileUtils.mkdir_p("#{root_dir}/html")
  end

  def self.output_dirs
    Asset.descendants.select { it.respond_to?(:output_dir) }.map { it.output_dir }.uniq
  end

  def update_html_link(node)
    node['data-w2p-class'] = self.class.name
    node['data-w2p-type'] = "asset"
    node['data-w2p-assetid'] = assetid.to_s
  end

  def self.count_with_subclasses(status = nil)
    types = [name] + descendants.map(&:name)
    assets = where(type: types)
    assets = assets.where(status: status) unless status.nil?
    assets.count
  end

  def self.pdf_relative_links(website, pdf_filename)
    # p "!!! pdf_relative_links #{pdf_filename}"
    doc = HexaPDF::Document.open(pdf_filename)
    file_prefix = "file://#{website.output_root_dir}/"
    doc.pages.each do |page|
      page[:Annots]&.each do |annot|
        next unless annot[:A]
        uri = annot[:A][:URI]
        # p "!!! uri #{uri}"
        # next unless uri.start_with?(file_prefix)
        depth = pdf_filename.count("/")
        # relative_prefix = "file://#{depth > 3 ? "../" : "./"}"
        relative_prefix = "#{depth > 3 ? "../" : "./"}"
        #relative_prefix = "file://#{depth > 3 ? "../" : "./"}"
        annot[:A][:URI] = uri.sub(file_prefix, relative_prefix)
        # p "!!! pdf_relative_links depth #{depth} before #{uri} after #{annot[:A][:URI]}"
      end
    end
    tmp_pdf_filename = "#{pdf_filename}-rel"
    doc.write(tmp_pdf_filename, optimize: true)
    FileUtils.mv(tmp_pdf_filename, pdf_filename)
  end

  private

  def self.stream_lines_for_url(url)
    p "!!! stream_lines_for_url #{url}"
    uri = URI(url)
    Enumerator.new do |yielder|
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request) do |response|
          buffer = +""
          response.read_body do |chunk|
            buffer << chunk
            while (line = buffer.slice!(/.*?\n/)) # yield full lines
              line = line.chomp.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
              yielder << line
            end
          end
          # Yield any trailing partial line.
          yielder << buffer unless buffer.empty?
        end
      end
    end
  end
end
