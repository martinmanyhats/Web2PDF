# frozen_string_literal: true

class Spider
  def initialize(website)
    @website = website
  end

  def spider_asset(asset)
    @asset = asset
    p "!!! Spider:spider_asset #{@asset.inspect}"
    raise "Spider:spider_asset not content asset #{@asset.inspect}" unless @asset.is_a?(ContentAsset)

    @asset.extract_content_info

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
    # p "!!! Spider:spider_link uri #{uri}"
    # p "!!! Spider:spider_link node #{node.inspect}"
    raise "Spider:spider_link nil uri #{uri}" if uri.nil?
    raise "Spider:spider_link url not interpolated #{uri} in assetid #{@asset.assetid}" if uri.path.include?("./?a=")

    unless @website.internal?(uri)
      node['data-w2p-type'] = "external"
      return
    end
    # Has broken links.
    return if @asset.asset_type == "DOL Google Sheet viewer"

    linked_asset = Asset.asset_for_uri(@website, uri)
    # p "!!! spider_link linked_asset #{linked_asset.inspect}"
    raise "Spider:spider_link missing asset uri #{uri} from @asset #{@asset.inspect}" if linked_asset.nil?

    # p "!!! Spider:spider_link linked_asset #{linked_asset.inspect}"
    if linked_asset.is_a?(RedirectPageAsset)
      # redirect_url will already contain resolved indirections, use that instead.
      p "!!! Spider:spider_link redirected linked_asset.redirect_url #{linked_asset.redirect_url}"
      unless @website.internal?(linked_asset.redirect_url)
        node['data-w2p-type'] = "external"
        node["href"] = linked_asset.redirect_url
        return
      end
      linked_asset = Asset.asset_for_uri(@website, URI.parse(linked_asset.redirect_url))
      raise "Spider:spider_link indirect missing asset uri #{uri}" if linked_asset.nil?
      if linked_asset.is_a?(RedirectPageAsset)
        unless @website.internal?(linked_asset.redirect_url)
          node['data-w2p-type'] = "external"
          node["href"] = linked_asset.redirect_url
          return
        end
        linked_asset = Asset.asset_for_uri(@website, URI.parse(linked_asset.redirect_url))
        raise "Spider:spider_link indirect missing asset uri #{uri}" if linked_asset.nil?
        raise "Spider:spider_link triple indirect" if linked_asset.is_a?(RedirectPageAsset)
      end
      p "!!! Spider:spider_link redirected linked_asset #{linked_asset.inspect}"
    end

    # linked_asset.extract_content_info if linked_asset.respond_to?(:extract_content_info)
    linked_asset.update_html_link(node)
    Rails.logger.silence { linked_asset.save! }
  end

  def XXgenerate(head: head, html_filename: nil, pdf_filename: nil)
    p "!!! generate id #{id} assetid #{assetid} #{html_filename} #{pdf_filename}"
    raise "Spider:generate unspidered id #{id}" if status == "unspidered"
    raise "Spider:generate missing head id #{id}" if head.nil?
    html_filename = asset.filename_with_assetid("html") if html_filename.nil?
    File.open(html_filename, "wb") do |file|
      file.write("<html>\n#{head}\n")
      body = Nokogiri::HTML("<div class='w2p-content'>#{content}</div>").css("body").first
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

  def generate_external_links(parsed_content)
    parsed_content.css("iframe").each do |iframe|
      p "!!! generate_external_links #{iframe["src"].inspect}"
      iframe.add_next_sibling("<p class='iframe-comment'>External URL: <a href='#{iframe["src"]}'>#{iframe["src"]}</a></p>")
    end
  end

  def XXgenerate_images(parsed_content)
    p "!!! generate_images"
  end

  def XXprocess_images(body)
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

  def XXspiderable_images(parsed_content)
    parsed_content.css("img").each do |image|
      p "!!! image src #{image["src"]}"
    end
  end

  def XXspiderable_external_elements(parsed_content)
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
