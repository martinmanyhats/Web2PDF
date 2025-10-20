# frozen_string_literal: true

class Spider
  def initialize(website)
    @website = website
  end

  def spider_asset(asset)
    @asset = asset
    p "!!! Spider:spider_asset #{@asset.inspect}"

    extract_standard_page_info

    doc = Nokogiri::HTML(@asset.content_html)
    spiderable_links(doc).each { spider_link(it) }

    @asset.status = "spidered"
    @asset.content_html = doc.to_html
    p "!!! Spider:spider_asset save #{@asset.assetid}"
    Rails.logger.silence do
      @asset.save!
    end
  end

  private

  def spiderable_links(doc)
    doc.css("a[href]")
       .select { it["href"].match?(%r{^https?://}) }
       .select { !it["href"].match?(%r{/(mainmenu|reports|sitemap|testing)}) }
       .compact
  end

  def spider_link(node)
    uri = uri_from_link_node(node)
    p "!!! Spider:spider_link uri #{uri}"
    # p "!!! Spider:spider_link node #{node.inspect}"
    raise "Spider:spider_link nil uri #{uri}" if uri.nil?
    raise "Spider:spider_link url not interpolated #{uri} in assetid #{@asset.assetid}" if uri.path.include?("./?a=")

    unless @website.internal?(uri)
      node['data-w2p-type'] = "external"
      return
    end
    # Has broken links.
    return if @asset.asset_type == "DOL Google Sheet viewer"

    linked_asset = asset_for_uri(uri)
    raise "Spider:spider_link missing asset uri #{uri} from @asset #{@asset.inspect}" if linked_asset.nil?

    p "!!! Spider:spider_link linked_asset #{linked_asset.inspect}"
    if linked_asset.redirect?
      # redirect_url will already contain resolved indirections, use that instead.
      p "!!! Spider:spider_link redirected linked_asset.redirect_url #{linked_asset.redirect_url}"
      unless @website.internal?(linked_asset.redirect_url)
        node['data-w2p-type'] = "external"
        node["href"] = linked_asset.redirect_url
        return
      end
      linked_asset = asset_for_uri(URI.parse(linked_asset.redirect_url))
      raise "Spider:spider_link indirect missing asset uri #{uri}" if linked_asset.nil?
      if linked_asset&.redirect?
        unless @website.internal?(linked_asset.redirect_url)
          node['data-w2p-type'] = "external"
          node["href"] = linked_asset.redirect_url
          return
        end
        linked_asset = asset_for_uri(URI.parse(linked_asset.redirect_url))
        raise "Spider:spider_link indirect missing asset uri #{uri}" if linked_asset.nil?
        raise "Spider:spider_link triple indirect" if linked_asset&.redirect?
      end
      p "!!! Spider:spider_link redirected linked_asset #{linked_asset.inspect}"
    end

    if linked_asset.content?
      if linked_asset.status != "spidered"
        linked_asset.status = "unspidered"
      end
      node['data-w2p-type'] = "content"
      node['data-w2p-assetid'] = linked_asset.assetid.to_s
    else
      p "!!! Spider:spider_link asset is not content assetid #{linked_asset.assetid} #{uri}"
      linked_asset.status = "linked"
      node['data-w2p-type'] = "data"
    end
    linked_asset.save!
  end

  def asset_for_uri(uri)
    return nil if uri.nil?
    uri = @website.normalize(uri)
    if uri.host != @website.host ||
       uri.path.blank? ||
       !(uri.scheme == "http" || uri.scheme == "https") ||
       uri.path.match?(%r{/(mainmenu|reports|sitemap|testing)})
      p "!!! Spider:asset_for_uri skipping #{uri}"
      return nil
    end
    AssetUrl.remap_and_find_by_uri(@asset, uri)&.asset
  end

  def generate(head: head, html_filename: nil, pdf_filename: nil)
    p "!!! generate id #{id} assetid #{assetid} #{html_filename} #{pdf_filename}"
    raise "Spider:generate unspidered id #{id}" if status == "unspidered"
    raise "Spider:generate missing head id #{id}" if head.nil?
    html_filename = asset.filename_with_assetid("html") if html_filename.nil?
    File.open(html_filename, "wb") do |file|
      file.write("<html>\n#{head}\n")
      body = Nokogiri::HTML("<div class='webpage-content'>#{content}</div>").css("body").first
      body["data-assetid"] = assetid_formatted
      body.first_element_child.before(Nokogiri::XML::DocumentFragment.parse(header_html))
      generate_html_links(body)
      generate_external_links(body)
      # generate_images(body)
      file.write(body.to_html)
      file.write("</html>\n")
      file.close
      save!
      Browser.instance.html_to_pdf(basename: asset.filename_base, html_filename: html_filename, pdf_filename: pdf_filename)
      return
    end
    raise "Spider:generate unable to create #{filename}"
  end

  def extract_standard_page_info
    p "!!! extract_standard_page_info asset #{@asset.inspect}"
    @asset.canonical_url = @asset.document.css("link[rel=canonical]").first["href"]
    timestamp = @asset.document.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value
    @asset.squiz_updated = DateTime.iso8601(timestamp) unless timestamp.blank?
    @asset.content_html = @asset.document.css("#main-content")&.inner_html
  end

  def generate_html_links(parsed_content)
    raise "NEEDS WORK"
    spiderable_link_elements(parsed_content).each do
      it.attributes["href"].value = generate_html_link(clean_link(it))
    end
  end

  def generate_html_link(url)
    p "!!! generate_html_link url #{url.inspect}"
    return "" if url.blank? # Faulty links in content.
    uri = website.normalize(url)
    asset = Asset.asset_for_uri(uri)
    p "!!! generate_html_link uri #{uri} asset #{asset.inspect}"
    return url if asset.nil?
    if asset.redirect_url
      p "!!! generate_html_link redirect #{asset.redirect_url}"
      # Spidering has already recursively resolved redirects, but it may be external.
      # TODO spider resolution needs to result in host path
      p "!!! website.normalize(asset.redirect_url).host #{website.normalize(asset.redirect_url).host}"
      # Do nothing if external URL.
      raise "NEEDS WORK"
      return asset.redirect_url if website.normalize(asset.redirect_url).host != website.host
      generate_html_link(asset.redirect_url)
    elsif asset.content_page?
      dest_page = Webpage.find_by(asset_id: asset.id)
      raise "Spider:generate_html_link cannot find dest_page assetid #{assetid} url #{link} uri #{uri}" unless dest_page
      p "!!! internally linking to #{uri.to_s} #{dest_page.title}"
      # asset_url = Asset.asset_url_for_uri(uri)
      # asset_url.webpage = self
      # asset_url.save!
      "#{website.web_root}/page/#{dest_page.asset.filename_base}.pdf"
    elsif asset.pdf?
      website.add_pdf(asset)
      "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}"
    elsif asset.image?
      website.add_image(asset)
      "#{website.web_root}/image/#{assetid_formatted}-#{asset.name}"
    elsif asset.office?
      website.add_office(asset)
      "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}.pdf"
    else
      p ">>>>>>>>>> IGNORING url #{url}"
      website.log(:ignored_links, "assetid #{assetid} url #{url}")
      url
    end
  end

  def generate_external_links(parsed_content)
    parsed_content.css("iframe").each do |iframe|
      p "!!! generate_external_links #{iframe["src"].inspect}"
      iframe.add_next_sibling("<p class='iframe-comment'>External URL: <a href='#{iframe["src"]}'>#{iframe["src"]}</a></p>")
    end
  end

  def generate_images(parsed_content)
    p "!!! generate_images"
  end

  def process_images(body)
    parsed_content.css("img").each do |image|
      p "!!! image #{image["src"]}"
      url = image["src"]
      case File.extname(url).downcase
      when ".jpg"
        p "!!! JPG"
      when ".png"
        p "!!! PNG"
      when ".gif"
        p "!!! GIF"
      else
        p "!!! unknown image type"
      end
    end
  end

  def XXspiderable_link_elements
    # Skip anchors and links with same page.
    Nokogiri::HTML(@asset.content_html).css("a[href]")
                                       .select { |a| !a["href"].start_with?("#") }
                                       .compact
                                       .map { clean_link(it) }
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

  def uri_from_link_node(node)
    # TODO remove anchor?
    URI.parse(node["href"].to_s.strip)
  end
end
