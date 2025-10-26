# frozen_string_literal: true

class ContentAsset < Asset
  scope :publishable, -> { where(status: "spidered") }

  def self.generate(assetids: nil)
    if assetids.nil?
      assets = ContentAsset.publishable
    else
      assets = ContentAsset.where(assetid: assetids)
    end
    assets.each do |asset|
      pdf_filename = asset.generate
      pdf_relative_links(asset.website, pdf_filename)
    end
  end

  def generate(head: head, html_filename: nil, pdf_filename: nil)
    p "!!! ContentAsset:with_root assetid #{assetid} html_filename #{html_filename} pdf_filename #{pdf_filename}"
    raise "ContentAsset:with_root unspidered assetid #{assetid}" if status == "unspidered"
    head = website.html_head(title: short_name) if head.nil?
    html_filename = filename_with_assetid("html", "html") if html_filename.nil?
    pdf_filename = filename_with_assetid(output_dir, "pdf") if pdf_filename.nil?
    p "!!! ContentAsset:with_root assetid #{assetid} html_filename #{html_filename} pdf_filename #{pdf_filename}"
    File.open(html_filename, "wb") do |file|
      file.write("<html>\n#{head}\n")
      body = Nokogiri::HTML("<div class='w2p-content'>#{content_html}</div>").css("body").first
      body["id"] = "w2p-page-#{assetid_formatted}"
      body["data-w2p-assetid"] = assetid_formatted
      body.first_element_child.before(Nokogiri::XML::DocumentFragment.parse(header_html))
      generate_html_links(body)
      generate_external_links(body)
      # generate_images(body) # TODO larger images?
      file.write(body.to_html)
      file.write("</html>\n")
      file.close
      save!
      Browser.instance.html_to_pdf(html_filename, pdf_filename)
    end
    pdf_filename
  end

  def header_html
    html_title = "<span class='w2p-title'>#{title}</span>"
    html_breadcrumbs = "<span class='w2p-breadcrumbs'>#{breadcrumbs_html}</span>"
    "<div class='w2p-header'>#{html_title}#{html_breadcrumbs}</div>"
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
    # TODO breadcrumbs if present
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

  def generated_filename
    raise "generated_filename website nil" if website.nil?
    raise "generated_filename website.output_root_dir nil" if website.output_root_dir.nil?
    "#{website.output_root_dir}/page/#{filename_base}.pdf"
  end

  def filename_base
    raise "ContentAsset:filename_base name missing" if name.nil?
    "#{assetid_formatted}-#{name.present? ? "#{safe_name}" : "untitled"}"
  end

  private

  def self.output_dir = "page"

  def generate_html_links(body)
    body.css("a[data-w2p-type]").each do |link|
      # p "!!! generate_html_links link #{link.inspect}"
      link_type = link["data-w2p-type"]
      case link_type
      when "asset"
        generate_asset_html_link(link)
      when "static"
        generate_static_html_link(link)
      when "external"
        # Nothing.
      else
        raise "ContentAsset:generate_html_links unexpected link_type #{link_type}"
      end
    end
  end

  def generate_asset_html_link(link)
    url = link["href"]
    raise "ContentAsset:generate_asset_html_link url missing in assetid #{assetid}" if url.blank?
    link_assetid = link.attributes["data-w2p-assetid"]&.value
    raise "ContentAsset:generate_asset_html_link missing link_assetid in #{assetid} url #{url}" if link_assetid.nil?
    linked_asset = Asset.find_by(assetid: link_assetid)
    # p "!!! linked_asset #{linked_asset.inspect}"
    case linked_asset
    when ContentAsset
      p "!!! generate_asset_html_link internally linking to content #{url} #{linked_asset.title}"
      link["href"] = "../page/#{linked_asset.filename_base}.pdf"
    when DataAsset
      data_url = "../#{linked_asset.output_dir}/#{linked_asset.filename_base}"
      p "!!! generate_asset_html_link internally linking #{url} to #{data_url}"
      link["href"] = data_url
    else
      raise "ContentAsset:generate_asset_html_link unexpected class"
    end
  end

  def generate_static_html_link(link)
    p "!!! generate_static_html_link link #{link.inspect}"
    link["href"] = "#{website.output_root_dir}#{link["href"]}"
  end

  def generate_external_links(parsed_content)
    parsed_content.css("iframe").each do |iframe|
      p "!!! generate_external_links #{iframe["src"].inspect}"
      iframe.add_next_sibling("<p class='iframe-comment'>External URL: <a href='#{iframe["src"]}'>#{iframe["src"]}</a></p>")
    end
  end

  def spiderable_link_elements(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("a[href]")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
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

  def breadcrumbs_html
    # p "!!! breadcrumbs_html #{squiz_breadcrumbs}"
    crumbs = Nokogiri::HTML(squiz_breadcrumbs).css("a").map do |crumb|
      "<span class='w2p-breadcrumb'><a href='#{crumb["href"]}'>#{crumb.text.strip}</a></span>"
    end
    crumbs.join("\n")
  end
end
