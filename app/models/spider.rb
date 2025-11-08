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
    # spider_static_links(doc)

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
       .select { !it["href"].match?(%r{/(mainmenu|reports|testing)}) }
       .compact
  end

  def spider_link(node)
    uri = uri_from_link_node(node)
    p "!!! Spider:spider_link uri #{uri}"
    # p "!!! Spider:spider_link node #{node.inspect}"
    raise "Spider:spider_link nil uri #{uri}" if uri.nil?
    raise "Spider:spider_link url not interpolated #{uri} in assetid #{@asset.assetid}" if uri.path.include?("./?a=")

    # Has broken links.
    return if @asset.asset_type == "DOL Google Sheet viewer"

    unless @website.internal?(uri)
      node['data-w2p-type'] = "external"
      return
    end

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
      linked_asset = Asset.asset_for_uri(@website, linked_asset.redirect_url)
      raise "Spider:spider_link indirect missing asset uri #{uri}" if linked_asset.nil?
      if linked_asset.is_a?(RedirectPageAsset)
        unless @website.internal?(linked_asset.redirect_url)
          node['data-w2p-type'] = "external"
          node["href"] = linked_asset.redirect_url
          return
        end
        linked_asset = Asset.asset_for_uri(@website, linked_asset.redirect_url)  # XYZ
        raise "Spider:spider_link indirect missing asset uri #{uri}" if linked_asset.nil?
        raise "Spider:spider_link triple indirect" if linked_asset.is_a?(RedirectPageAsset)
      end
      p "!!! Spider:spider_link redirected linked_asset #{linked_asset.inspect}"
    end

    linked_asset.update_html_link(node)
    Rails.logger.silence do
      Link.create!(source: @asset, destination: linked_asset)
      linked_asset.save!
    end
  end

  def spider_static_links(doc)
    @_static_pattern ||= begin
                           pattern = "^#{@website.url}/(sitemap)$"
                           Regexp.new(pattern)
                         end
    # p "!!! Spider:spider_static_links #{@_static_pattern.inspect}"
    doc.css("a[href]")
       .select { it["href"].match?(@_static_pattern) }
       .each do |node|
      node['data-w2p-type'] = "static"
      name = node["href"].match(@_static_pattern)[1]
      p "=============== spider_static_links name #{name}"
      case name
      when "sitemap"
        node["href"] = "/sitemap.pdf"
      else
        raise "Spider:spider_static_links unknown static link #{name}"
      end
    end
  end

  def generate_external_links(parsed_content)
    parsed_content.css("iframe").each do |iframe|
      p "!!! generate_external_links #{iframe["src"].inspect}"
      iframe.add_next_sibling("<p class='iframe-comment'>External URL: <a href='#{iframe["src"]}'>#{iframe["src"]}</a></p>")
    end
  end

  def uri_from_link_node(node)
    # TODO remove anchor?
    URI.parse(node["href"].to_s.strip)
  end
end
