# frozen_string_literal: true

class ContentAsset < Asset
  scope :publishable, -> { where(status: "spidered") }

  FIXED_ASSETS = {
    home: 93,
    acrobat: 164,
    archived_material: 1472,
    sitemap: 15632,
    page_not_found: 13267,
    parish_archive_register: 14047,
    introduction: 19273,
    external_assets: 19288
  }.freeze

  def self.suffix = "html"
  def self.output_dir = "page"
  def asset_link_type = "intasset"

  def self.sitemap_ordered
    assets = ContentAsset.sitemap.spiderable_link_elements(Nokogiri::HTML(ContentAsset.sitemap.content_html)).map do |link|
      assetid = link["data-w2p-assetid"]
      next if assetid.nil?
      ContentAsset.find_by(assetid: assetid) # Which is nil for non-content links eg PDF.
    end.compact.uniq
    assets.prepend(ContentAsset.introduction)
    assets.append(*additional_assets)
    p "!!! ContentAsset:sitemap_ordered size #{assets.size}"
    assets
  end

  def self.additional_assets
    [ContentAsset.acrobat, ContentAsset.archived_material]
  end

  def generate(head: head, html_filename: nil, pdf_filename: nil, preface_html: nil)
    raise "ContentAsset:generate unspidered assetid #{assetid}" if status == "unspidered"
    head = website.html_head(short_name) if head.nil?
    html_filename = filename_with_assetid(suffix: "html") if html_filename.nil?
    pdf_filename = generated_filename if pdf_filename.nil?
    p "!!! ContentAsset:generate assetid #{assetid} html_filename #{html_filename} pdf_filename #{pdf_filename}"
    File.open(html_filename, "wb") do |file|
      file.write("<html>\n#{head}\n")
      @content_body = Nokogiri::HTML("<div class='w2p-content'>#{content_html}</div>").css("body").first
      @content_body["id"] = "w2p-page-#{assetid_formatted}"
      @content_body["data-w2p-assetid"] = assetid_formatted
      @content_body.first_element_child.before(Nokogiri::XML::DocumentFragment.parse(header_html))
      @content_body.first_element_child.after(Nokogiri::XML::DocumentFragment.parse("<div class='w2p-preface'>#{preface_html}</div>")) if preface_html
      generate_html_links
      generate_iframe_links
      # generate_images # TODO larger images?
      file.write(@content_body.to_html)
      file.write("</html>\n")
      file.close
      save!
      Browser.instance.html_to_pdf(html_filename, pdf_filename)
    end
    Asset::pdf_relative_links(website, pdf_filename)
  end

  def header_html
    html_title = "<span class='w2p-title'>#{title}</span>"
    if home?
      breadcrumb_assets = []
    else
      breadcrumb_assets = Nokogiri::HTML(breadcrumbs_html).css("a").map do |crumb|
        linked_asset = Asset.asset_for_uri(website, crumb.attributes["href"].value)  # XYZ
        raise "ContentAsset:header_html cannot find asset url #{crumb.attributes["href"]}" if linked_asset.nil?
        if linked_asset.is_a?(RedirectPageAsset)
          p "!!! header_html redirection from #{linked_asset.assetid}"
          linked_asset = Asset.asset_for_uri(website, linked_asset.redirect_url)  # XYZ
          raise "ContentAsset:header_html cannot find redirect_url #{linked_asset.redirect_url}" if linked_asset.nil?
        end
        linked_asset
      end
      if breadcrumb_assets.present?
        breadcrumb_assets.prepend(ContentAsset.home) unless breadcrumb_assets.first.home?
      else
        breadcrumb_assets = [ContentAsset.home] unless introduction?
      end
    end
    crumbs = breadcrumb_assets.map do |linked_asset|
      "<span class='w2p-breadcrumb'><a href='intasset://#{linked_asset.assetid}:#{assetid}'>#{linked_asset.short_name}</a></span>"
    end
    "<div class='w2p-header'>#{html_title}#{"<span class='w2p-breadcrumbs'>#{crumbs.join(" > ")}</span>"}</div>"
  end

  def extract_content_info
    # p "!!! extract_content_info assetid #{assetid}"
    url = document.css("link[rel=canonical]").first["href"]
    raise "Asset:extract_content_info missing canonical URL #{assetid}" if url.nil?
    self.canonical_url = url
    timestamp = document.css("meta[name='squiz-updated_iso8601']").first
    raise "Asset:extract_content_info missing timestamp #{assetid}" if timestamp.nil?
    self.squiz_updated = DateTime.iso8601(timestamp["content"])
    main_content = document.css("#main-content")
    raise "Asset:extract_content_info missing main-content #{assetid}" if main_content.nil?
    self.content_html = main_content.inner_html
    breadcrumbs = document.css("#breadcrumbs")
    self.breadcrumbs_html = breadcrumbs unless breadcrumbs.nil?
  end

  def document
    @_document ||=
      begin
        uri = URI.parse("#{asset_urls.first.url}")
        # p ">>>>>>>>>>>>>>>>>>>> document HTTParty.get uri #{uri}"
        response = HTTParty.get(uri, {
          headers: Website.http_headers,
        })
        # TODO: error checking, retry
        Nokogiri::HTML(response.body)
      end
  end

  def update_html_link(node)
    self.status = "unspidered" if status != "spidered"
    super
  end

  def sort_order
    sitemap_links = spiderable_link_elements(Nokogiri::HTML(Asset.sitemap.content_html))
    @sitemap_asset_depth_by_assetid = {}
    sitemap_links.each do |link|
      depth = sitemap_depth(link)
      assetid = link["data-w2p-assetid"]
      #p "!!! depth #{depth} assetid #{assetid}"
      @sitemap_asset_depth_by_assetid[assetid] = depth
    end
    p "!!! sitemap_asset_depth_by_assetid.size #{@sitemap_asset_depth_by_assetid.size}"
    sitemap_assetids = @sitemap_asset_depth_by_assetid.keys
    non_sitemap_content_assetids = ContentAsset.where(status: "scraped").pluck(:assetid) - sitemap_assetids
    raise "ContentAsset:sort_order non_sitemap_content_assetids #{non_sitemap_content_assetids.join(" ")}" unless non_sitemap_content_assetids.empty?
  end

  def sitemap_depth(link)
    link.ancestors("tr").size - 2
  end

  def filename_base
    raise "ContentAsset:filename_base name missing" if name.nil?
    "#{assetid_formatted}-#{name.present? ? "#{safe_name}" : "untitled"}"
  end

  def add_footer? = true

  def spiderable_link_elements(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("a[href]")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
  end

  FIXED_ASSETS.keys.each do |name|
    define_singleton_method name.to_sym do
      # p "!!! #{name} const #{FIXED_ASSETS[name]}"
      ContentAsset.find_by(assetid: FIXED_ASSETS[name])
    end
    define_method "#{name}?".to_sym do
      # p "!!! #{name}? assetid #{assetid} vs #{FIXED_ASSETS[name]}"
      assetid == FIXED_ASSETS[name]
    end
  end

  private

  def generate_html_links
    @content_body.css("a[data-w2p-type]").each do |link|
      # p "!!! generate_html_links link #{link.inspect}"
      link_type = link["data-w2p-type"]
      case link_type
      when "asset"
        generate_asset_link(link)
      when "external"
        generate_external_link(link)
      else
        raise "ContentAsset:generate_html_links unexpected link_type #{link.inspect}"
      end
    end
  end

  def generate_asset_link(link)
    url = link["href"]
    raise "ContentAsset:generate_asset_link url missing in assetid #{assetid}" if url.blank?
    link_assetid = link.attributes["data-w2p-assetid"]&.value
    raise "ContentAsset:generate_asset_link missing data-w2p-assetid in #{assetid} url #{url}" if link_assetid.nil?
    linked_asset = Asset.find_by(assetid: link_assetid)
    raise "ContentAsset:generate_asset_link link #{link_assetid} not found" if linked_asset.nil?
    # p "!!! generate_asset_link linked_asset #{linked_asset.inspect}"
    link["href"] = "#{linked_asset.asset_link_type}://#{link_assetid}:#{assetid}"
    if linked_asset.external_asset?
      # Append assetid to link contents.
      link.add_child(Nokogiri::HTML::DocumentFragment.parse("<span class='w2p-extassetid'>[##{linked_asset.assetid}]</span>"))
    end
  end

  def generate_external_link(link)
    # p "!!! generate_external_link link #{link.inspect}"
    # TODO
  end

  def generate_iframe_links
    @content_body.css("iframe").each do |iframe|
      p "!!! generate_iframe_links #{iframe["src"].inspect}"
      iframe.add_next_sibling("<p class='iframe-comment'>External URL: <a href='#{iframe["src"]}'>#{iframe["src"]}</a></p>")
    end
  end

  def spiderable_images(parsed_content)
    parsed_content.css("img").each do |image|
      p "!!! image src #{image["src"]}"
    end
  end

  def spiderable_external_elements(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("iframe")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
  end

  def clean_url_from_link(node)
    # TODO remove anchor?
    node["href"].to_s.strip
  end
end
