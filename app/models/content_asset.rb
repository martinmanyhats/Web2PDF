# frozen_string_literal: true

class ContentAsset < Asset
  def self.generate(assetids: nil, head: head, html_filename: nil, pdf_filename: nil)
    if assetids.nil?
      assets = ContentAsset.where(status: "spidered")
    else
      assets = ContentAsset.where(assetid: assetids)
    end
    assets.each { it.generate(head: head, html_filename: html_filename, pdf_filename: pdf_filename) }
    # generate_data_toc
  end

  def generate(head: head, html_filename: nil, pdf_filename: nil)
    p "!!! ContentAsset:generate assetid #{assetid}"
    raise "ContentAsset:generate unspidered assetid #{assetid}" if status == "unspidered"
    head = website.html_head(title: short_name) if head.nil?
    html_filename = filename_with_assetid("html") if html_filename.nil?
    File.open(html_filename, "wb") do |file|
      file.write("<html>\n#{head}\n")
      body = Nokogiri::HTML("<div class='w2p-content'>#{content_html}</div>").css("body").first
      body["data-w2p-assetid"] = assetid_formatted
      body.first_element_child.before(Nokogiri::XML::DocumentFragment.parse(header_html))
      generate_html_links(body)
      generate_external_links(body)
      # generate_images(body)
      file.write(body.to_html)
      file.write("</html>\n")
      file.close
      save!
      Browser.instance.html_to_pdf(html_filename, pdf_filename)
      return
    end
    raise "ContentAsset:generate unable to create #{filename}"
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
        p ">>>>>>>>>>>>>>>>>>>> document HTTParty.get uri #{uri}"
        response = HTTParty.get(uri, {
          headers: Website.http_headers,
        })
        # TODO: error checking, retry
        # p "!!! Website:content_for_url headers #{response.headers}"
        # p "!!! Website:content_for_url body #{response.body.truncate(8000)}"
        Nokogiri::HTML(response.body)
      end
  end

  def update_html_link(node)
    self.status = "unspidered" if status != "spidered"
    super
  end

  private

  def self.output_dir = "page"

  def generate_html_links(body)
    body.css("a[data-w2p-type]").each do |link|
      p "!!! generate_html_links link #{link.inspect}"
      url = link["href"]
      raise "ContentAsset:generate_html_links url missing in assetid #{assetid}" if url.blank?
      link_type = link["data-w2p-type"]
      next if link_type == "external"
      # next if url.blank? # Faulty links in content.
      link_assetid = link.attributes["data-w2p-assetid"]&.value
      raise "ContentAsset:generate_html_links missing link_assetid in #{assetid} url #{url}" if link_assetid.nil?
      p "!!! generate_html_links assetid #{assetid} link_assetid #{link_assetid} url #{url}"
      linked_asset = Asset.find_by(assetid: link_assetid)
      p "!!! linked_asset #{linked_asset.inspect}"
      case linked_asset
      when ContentAsset
        p "!!! internally linking to content #{url} #{linked_asset.title}"
        link.attributes["href"].value = generated_filename
      when DataAsset
        p "!!! internally linking to data #{url}"
        link.attributes["href"].value = "#{website.web_root}/page/#{filename_base}.pdf"
      end
      p "!!! BODY #{body.to_html}"
    end
  end

  def generated_filename
    "#{website.web_root}/page/#{filename_base}.pdf"
  end

=begin
  def XXgenerate_html_link(url)
    p "!!! generate_html_link url #{url.inspect}"
    return "" if url.blank? # Faulty links in content.
    uri = website.normalize(url)
    asset = Asset.asset_for_uri(website, uri)
    p "!!! generate_html_link uri #{uri} asset #{asset.inspect}"
    return url if asset.nil?
    if asset.redirect_url
      p "!!! generate_html_link redirect #{asset.redirect_url}"
      # Spidering has already recursively resolved redirects, but it may be external.
      # TODO spider resolution needs to result in host path
      p "!!! website.normalize(asset.redirect_url).host #{website.normalize(asset.redirect_url).host}"
      # Do nothing if external URL.
      return asset.redirect_url if website.normalize(asset.redirect_url).host != website.host
      return generate_html_link(asset.redirect_url)
    elsif asset.content_page?
      dest_page = Webpage.find_by(asset_id: asset.id)
      raise "Webpage:generate_html_link cannot find dest_page assetid #{assetid} link #{link} uri #{uri}" unless dest_page
      p "!!! internally linking to #{uri.to_s} #{dest_page.title}"
      # asset_url = Asset.asset_url_for_uri(uri)
      # asset_url.webpage = self
      # asset_url.save!
      return "#{website.web_root}/page/#{dest_page.asset.filename_base}.pdf"
    elsif asset.pdf?
      website.add_pdf(asset)
      return "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}"
    elsif asset.image?
      website.add_image(asset)
      return "#{website.web_root}/image/#{assetid_formatted}-#{asset.name}"
    elsif asset.office?
      website.add_office(asset)
      return "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}.pdf"
    else
      p ">>>>>>>>>> IGNORING url #{url}"
      website.log(:ignored_links, "assetid #{assetid} url #{url}")
      return url
    end
  end
=end

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
