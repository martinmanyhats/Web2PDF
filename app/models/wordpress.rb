# frozen_string_literal: true

class Wordpress
  WP_BASE = "https://wpdh.martinreed.co.uk/wp-json/wp/v2"

  def initialize(username:, application_password:)
    p "Wordpress username #{username}"
    @auth_header = "Basic #{Base64.strict_encode64("#{username}:#{application_password}")}"
  end

  def upload_content(website, assets)
    p "upload_content assetid #{assets.first(5).inspect}"
    host_regex = %r{#{website.url}/}
    p "host_regex #{host_regex}"
    assets.each do |asset|
      p "assetid #{asset.assetid} canonical_url #{asset.canonical_url}"
      # content = File.read(asset.filename_with_assetid(suffix: "html"))
      content = upload_linked_assets(website, asset.content_html)
      slug = asset.canonical_url.gsub(host_regex, '')
      create_page(website, asset.canonical_url, asset.short_name, slug: slug, content: content)
    end
  end

  def create_page(website, squiz_url, title, slug:, content:, status: "publish")
    slug = title unless slug.present?
    # content =  format_for_wordpress(website, content)
    begin
      payload = {
        title: title,
        slug: slug,
        content: content,
        status: status
      }
      response = connection.post("pages") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
      end
      response = handle_response(response)
      WordpressItem.create!(itemid: response["id"].to_i, squiz_url: squiz_url, slug: response["slug"], url: response["guid"]["raw"])
    rescue => e
      raise "Wordpress:create_page failed #{title} #{slug} #{e.inspect}"
    end
  end

  def upload_linked_assets(website, content)
    doc = Nokogiri::HTML(content)
    p "!!! upload_linked_assets a[href] #{doc.css("a[href]").inspect}"
    internal_links = doc.css("a[href]")
                        .select { it["href"].match?(%r{^https?://}) }
                        .select { !it["href"].match?(%r{/(mainmenu|reports|testing)}) }
                        .select { website.internal?(it["href"]) }
    p "!!! internal links count #{internal_links.count}"
    internal_links.each do |link|
      squiz_url = link["href"]
      p "!!! link #{squiz_url}"
      raise "Wordpress:upload_linked_assets blank href #{link.inspect}" if squiz_url.blank?
      if squiz_url =~ /\.(jpg,jpeg,gif,png)$/
        p "!!! href image #{squiz_url}"
        wpitem = upload_image(squiz_url)
        link["href"] = wpitem.url
      else
        p "<<<<< href squiz_url #{squiz_url}"
        # link["href"] = future_wp_url
      end
    end

    p "!!! images #{doc.css("img[src]")}"
    image_links = doc.css("img[src]")
                     .select { website.internal?(it["src"]) }
    p "!!! images count #{image_links.count}"
    image_links.each do |img|
      p "!!! img #{img}"
      squiz_url = img["src"]
      p "!!! squiz_url #{squiz_url}"
      raise "Wordpress:upload_linked_assets blank href #{img.inspect}" if squiz_url.blank?
      if squiz_url =~ %r{\.(jpg|jpeg|gif|png)$}i
        p "!!! img image #{squiz_url}"
        p "!!! img alt #{img["alt"]}"
        wpitem = upload_image(squiz_url, alt: img["alt"])
        img["src"] = wpitem.url
      else
        raise "Wordpress:upload_linked_asset unknown image type #{img}"
      end
    end
    p "!!! upload_linked_assets doc #{doc.to_s}"
    doc.to_s
  end

  def upload_image(squiz_url, alt: nil)
    match = squiz_url.match(%r{__data/assets/image/(\d+)/(?<id>\d+)})
    raise "Wordpress:upload_image missing assetid #{squiz_url}" if match[:id].blank?
    p "!!! match[:id] #{match[:id]}"
    asset = Asset.find_by(assetid: match[:id])
    raise "Wordpress:upload_image missing asset #{squiz_url}" unless asset
    response = upload_media_asset(squiz_url, title: asset.short_name, alt: alt, assetid: asset.assetid)
    p "!!! asset uploaded #{asset.assetid} response #{response.inspect}"
    WordpressItem.create!(itemid: response["id"].to_i, slug: response["slug"], url: response["guid"]["raw"], squiz_url: squiz_url)
  end

  def upload_media_asset(url, title: nil, alt: nil, assetid: nil)
    raise "Wordpress:upload_media_asset missing url" unless url
    begin
      p "upload_media #{url} mime_type #{mime_type(url)}"
      data = StringIO.new(URI.open(url).read)
    rescue => e
      raise "Wordpress:upload_media_asset file not loaded #{url} #{e.inspect}"
    end
    begin
      file = Faraday::Multipart::FilePart.new(
        data,
        mime_type(url),
        File.basename(url)
      )
      payload = { file: file }
      payload[:title] = title if title
      payload[:alt_text] = alt if alt
      payload[:caption] = alt if alt
      p "!!! payload #{payload.inspect}"
      upload_response = connection.post("media", payload)
      upload_response = handle_response(upload_response)
    rescue => e
      raise "Wordpress:upload_media_asset unable to upload #{url}: #{e.inspect}"
    end
    if assetid
      begin
        payload = {
          post_id: upload_response["id"],
          assetid: assetid
        }
        connection.post("/wp-json/squiz/v2/asset", payload)
      rescue => e
        raise "Wordpress:upload_media_asset unable to set assetid #{url}: #{e.inspect}"
      end
    end
    upload_response
  end

  private

  def connection
    conn = Faraday.new(url: WP_BASE) do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.headers
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

  def XXformat_for_wordpress(website, content)
    doc = Nokogiri::HTML(content)
    doc.css("img").each do |img|
      src = img.attr("src")
      p "!!! img src #{src}"
      assetid = Asset.assetid_from_url(src)
      linked_asset = Asset.find_by(assetid: assetid)
      p "!!! linked_asset #{linked_asset.inspect}"
      raise "Wordpress:format_for_wordpress missing linked_asset" unless linked_asset
      item = linked_asset.wordpress_item
      p "!!! item #{item.inspect}"
      raise "Wordpress:format_for_wordpress missing wordpress_item" unless item
      response = connection.get("media/#{item.itemid}")
      p "!!! response #{response.inspect}"
    end
    doc.css("a[data-w2p-type]").each do |link|

    end
  end

  private

  def assetid_from_url

  end
end