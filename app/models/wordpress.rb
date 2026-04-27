# frozen_string_literal: true

class Wordpress
  WP_API_BASE = "/wp-json/wp/v2"

  def initialize(hostname, username:, application_password:)
    @wp_api_url = "https://#{hostname}#{WP_API_BASE}"
    @auth_header = "Basic #{Base64.strict_encode64("#{username}:#{application_password}")}"
    p "Wordpress @wp_api_url #{@wp_api_url} username #{username}"
  end

  def upload_static_media
    Dir.glob(Rails.root.join("wordpress/static_media/*")).each do |path|
      next unless File.file?(path)
      filename = File.basename(path)
      slug = filename.gsub(%r{\.}, "-")
      p "!!! upload_static_media path #{path} filename #{filename}"
      File.open(path, "rb") do |data|
        upload_media(data, mime_type(filename), filename, slug)
      end
    end
  end

  def upload_image_assets(assets)
    assets.each do |asset|
      upload_media_asset(asset)
    end
    upload_static_media
  end

  def upload_file_assets(assets)
    assets.each do |asset|
      upload_media_asset(asset)
    end
  end

  def upload_content_pages(website, assets)
    assets.each do |asset|
      updated_doc = process_linked_assets(asset)
      create_page(asset, content: updated_doc.to_s)
    end
  end

  #private

  def upload_media_asset(asset)
    raise "Wordpress:upload_media_asset missing url #{asset.assetid}" unless asset.url
    begin
      p "upload_media #{asset.url} mime_type #{mime_type(asset.url)}"
      data = StringIO.new(URI.open(asset.url).read)
    rescue => e
      raise "Wordpress:upload_media_asset file not loaded #{asset.assetid} #{e.inspect}"
    end
    name = "#{asset.assetid}-#{File.basename(asset.url)}"
    slug = wordpress_slug(asset)
    upload_response = upload_media(data, mime_type(asset.url), name, slug)
    create_wordpress_item(upload_response["id"].to_i, upload_response["link"], upload_response["slug"], asset)
    upload_response
  end

  def upload_media(data, mime_type, name, slug)
    begin
      file = Faraday::Multipart::FilePart.new(
        data,
        mime_type,
        name
      )
      payload = {
        file: file,
        slug: slug,
        title: name,
        alt: name
      }
      p "!!! upload_media payload #{payload.inspect}"
      upload_response = connection.post("media", payload)
      upload_response = handle_response(upload_response)
      raise "Wordpress:upload_media slug mismatch #{slug}:#{upload_response["slug"]} #{name}" if slug != upload_response["slug"]
    rescue => e
      raise "Wordpress:upload_media unable to upload #{name}: #{e.inspect}"
    end
    upload_response
  end

  def process_linked_assets(content_asset)
    doc = Nokogiri::HTML(content_asset.content_html)
    updated_doc = update_internal_links(content_asset, doc)
    update_image_links(content_asset, updated_doc)
  end

  def update_internal_links(content_asset, doc)
    p "!!! update_internal_links assetid #{content_asset.assetid}"
    internal_links = doc.css("a[href]")
                        .select { it["href"].match?(%r{^https?://}) }
                        .select { !it["href"].match?(%r{/(mainmenu|reports|testing)}) }
                        .select { content_asset.website.internal?(it["href"]) }
    p "!!! internal links count #{internal_links.count}"
    bad_links = []
    internal_links.each do |link|
      squiz_url = link["href"]
      p "!!! link #{squiz_url}"
      raise "Wordpress:update_internal_links blank href #{link.inspect}" if squiz_url.blank?
      if squiz_url =~ /\.(jpg,jpeg,gif,png)$/
        raise "Wordpress:update_internal_links found link to image #{content_asset.assetid} #{squiz_url}"
      else
        p "<<<<< href squiz_url #{squiz_url}"
        asset = Asset.asset_for_uri(content_asset.website, squiz_url)
        if asset
          while asset.is_a?(RedirectPageAsset)
            asset = Asset.asset_for_uri(content_asset.website, asset.redirect_url)
            p "@@@ redirecting to #{asset.assetid} #{asset.url}"
          end
          p "!!! assetid #{asset.assetid}"
          # Link to what the Wordpress URL will be.
          link["href"] = "#{@wp_api_url}/#{wordpress_slug(asset)}"
        else
          # raise "Wordpress:update_internal_links missing asset url #{squiz_url}"
          bad_links << squiz_url
        end
      end
    end
    if bad_links.present?
      p "!!! bad_links #{bad_links.count}"
      bad_links.each { p "!!!  #{it}" }
      raise "Wordpress:update_internal_links bad_links #{bad_links.count}"
    end
    doc
  end

  def update_image_links(content_asset, doc)
    image_links = doc.css("img[src]")
                     .select { content_asset.website.internal?(it["src"]) }
    image_links.each do |img|
      # p "!!! img #{img}"
      squiz_url = img["src"]
      # p "!!! squiz_url #{squiz_url}"
      raise "Wordpress:update_image_links blank href #{img.inspect}" if squiz_url.blank?
      if squiz_url =~ %r{__data/.*\.(jpg|jpeg|gif|png)$}i
        asset = ImageAsset.asset_from_data_url(squiz_url)
        img["src"] = asset.wordpress_item.url
      elsif squiz_url =~ %r{__lib/}
        p "!!! update_images_links __lib assetid #{content_asset.assetid} #{squiz_url}"
      else
        raise "Wordpress:update_image_links unknown image in assetid #{content_asset.assetid} #{img}"
      end
    end
    # p "!!! update_image_links doc #{doc.to_s}"
    doc
  end

  def create_page(asset, content: nil, status: "publish")
    content = asset.content_html if content.nil?
    content = extract_body(content)
    content << asset.clean_breadcrumbs_html
    p "!!! content #{content}"
    p "!!! create_page assetid #{asset.assetid} canonical_url #{asset.canonical_url}"
    begin
      slug = wordpress_slug(asset)
      payload = {
        title: asset.title,
        slug: slug,
        content: content,
        status: status
      }
      response = connection.post("pages") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
      end
      response = handle_response(response)
      raise "Wordpress:create_page slug mismatch #{slug} #{response["slug"]}" if slug != response["slug"]
      create_wordpress_item(response["id"].to_i, response["link"], response["slug"], asset)
    rescue => e
      raise "Wordpress:create_page failed #{asset.title} #{payload.inspect} #{e.inspect}"
    end
  end

  def create_wordpress_item(itemid, url, slug, asset)
    wpitem = WordpressItem.create!(itemid: itemid, url: url, slug: slug, asset: asset)
    set_assetid(wpitem, asset.assetid)
  end

  def set_meta(wpitem, assetid, additional_meta = {})
    raise "Wordpress:set_meta missing assetid" unless assetid
    begin
      payload = {
        post_id: wpitem.itemid,
        assetid: assetid
      }
      payload[:additional_meta] = additional_meta
      response = connection.post("/wp-json/squiz/v2/asset_meta", payload) do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = payload.to_json
      end
      p "!!! set_meta response #{response.inspect}"
      raise "Wordpress:set_meta status failed #{response.inspect}" if response.status != 200
      response = JSON.parse(response.body)
      p "!!! set_meta response #{response.inspect}"
      raise "Wordpress:set_meta response #{response["ok"]} error #{response["error"]}" unless response["ok"]
      # raise "Wordpress:set_meta error #{assetid} wpid #{wpitem.id} response #{response}"
    rescue => e
      raise "Wordpress:set_meta unable to set assetid #{assetid} wpid #{wpitem.id}: #{e.inspect}"
    end
  end

  def set_assetid(wpitem, assetid)
    raise "Wordpress:set_assetid missing assetid" unless assetid
    begin
      payload = {
        post_id: wpitem.itemid,
        assetid: assetid
      }
      response = connection.post("/wp-json/squiz/v2/asset", payload) do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = payload.to_json
      end
      p "!!! set_assetid response #{response.inspect}"
    rescue => e
      raise "Wordpress:set_assetid unable to set assetid #{assetid} wpid #{wpitem.id}: #{e.inspect}"
    end
  end

  def connection
    retry_options = {
      max: 3,
      interval: 0.5,
      interval_randomness: 0.5,
      backoff_factor: 2,
      retry_block: -> (env:, options:, retry_count:, exception:, will_retry_in:) { p ">>>>>> retrying #{retry_count} after #{exception.inspect}" }
    }
    conn = Faraday.new(url: @wp_api_url) do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.headers
      f.request :retry, retry_options
    end
    conn.headers["Authorization"] = @auth_header
    conn
  end

  def handle_response(response)
    raise "WordPress request failed: #{response.status} #{response.body}" unless response.success?
    JSON.parse(response.body)
  end

  def mime_type(path)
    case File.extname(path).downcase
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".png" then "image/png"
    when ".gif" then "image/gif"
    when ".webp" then "image/webp"
    else "application/octet-stream"
    end
  end

  def wordpress_slug(asset)
    raise "Wordpress:wordpress_slug url missing" if asset.url.blank?
    slug = asset.website.normalize(asset.url).path.gsub(%r{^/}, "")
    # p "!!! pre-slug #{slug}"
    slug = slug.downcase
               .gsub(DataAsset::URL_REGEX, '\k<assetid>-\k<filename>')
               .gsub(%r{[^a-z0-9\s\-_/]}, "")
               .gsub(%r{[\s\-_/]+}, "-")
               .gsub(/\A-+|-+\z/, "")
    p "!!! slug #{slug}"
    slug
  end

  def extract_body(html, remove_sup: false)
    doc = Nokogiri::HTML(html)

    body = doc.at("body")
    raise "Wordpress:extract_body missing body" unless body

    # =========================================================
    # 0. PREVENT WORDPRESS wpautop FROM TURNING LINE BREAKS
    #    INSIDE TEXT NODES INTO <br>
    # =========================================================

    body.traverse do |node|
      next unless node.text?
      next if node.ancestors.any? { |a| %w[pre code textarea script style].include?(a.name) }
      node.content = node.content
                         .gsub(/\r\n?/, "\n")          # normalize CRLF / CR
                         .gsub(/[ \t]*\n+[ \t]*/, " ") # collapse line breaks to spaces
                         .gsub(/[ \t]{2,}/, " ")       # collapse repeated spaces
    end

    # =========================================================
    # 1. STABILISE ANCHOR → TEXT BOUNDARIES
    # =========================================================
    #
    # Insert a normal space after <a> elements inside list items.
    # This forces Chrome to break the text run safely.
    #

    body.css("li a").each do |a|
      next_sibling = a.next_sibling

      # Only add space if not already present
      unless next_sibling&.text? && next_sibling.text.start_with?(" ")
        a.add_next_sibling(Nokogiri::XML::Text.new(" ", doc))
      end
    end

    # =========================================================
    # 2. OPTIONAL: FLATTEN ORDINAL SUPERSCRIPTS
    # =========================================================

    if remove_sup
      body.css("sup").each do |node|
        if node.text.match?(/\A(st|nd|rd|th)\z/i)
          node.replace(Nokogiri::XML::Text.new(node.text, doc))
        end
      end
    end

    # =========================================================
    # 3. WRAP BODY CONTENT
    # =========================================================

    wrapper = Nokogiri::XML::Node.new("div", doc)
    wrapper["class"] = "squiz-body"

    body.children.to_a.each do |child|
      wrapper.add_child(child)
    end

    body.replace(wrapper)

    wrapper.to_html
  end
end