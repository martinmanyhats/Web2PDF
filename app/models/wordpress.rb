# frozen_string_literal: true

class Wordpress
  WP_BASE = "https://wpdh.martinreed.co.uk/wp-json/wp/v2"

  def initialize(username:, application_password:)
    p "Wordpress username #{username}"
    @auth_header = "Basic #{Base64.strict_encode64("#{username}:#{application_password}")}"
  end

  def upload_standard_page_assets(assets)
    p "upload_standard_page assetid #{assets.first(5).inspect}"
    host_regex = %r{#{assets[0].website.url}/}
    p "host_regex #{host_regex}"
    assets.each do |asset|
      p "assetid #{asset.assetid} canonical_url #{asset.canonical_url}"
      slug = asset.canonical_url.gsub(host_regex, '')
      create_page(title: asset.short_name, slug: slug, content: asset.content_html)
    end
  end

  def create_page(title:, slug:, asset:, status: "publish")
    slug = title unless slug.present?
    content = asset.filename_with_assetid.read
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
    handle_response(response)
  end

  def upload_image_assets(assets)
    assets.each do |asset|
      response = upload_media_asset(asset.asset_urls&.first&.url, title: asset.short_name)
      p "!!! asset_id #{asset.assetid} response #{response.inspect}"
      asset.create_wordpress_item(itemid: response["id"], slug: response["slug"], url: response["guid"]["raw"])
    end
  end

  def upload_media_asset(url, title: nil, alt_text: nil)
    raise "Wordpress:upload_media_asset missing asset url #{asset.assetid}" unless url
    begin
    rescue => e
      raise "Wordpress:upload_media_asset file not loaded #{file_path}" if data.empty?
    end
    p "upload_media #{url} mime_type #{mime_type(url)}"
    data = StringIO.new(URI.open(url).read)
    file = Faraday::Multipart::FilePart.new(
      data,
      mime_type(url),
      File.basename(url)
    )
    payload = { file: file }
    payload[:title] = title if title
    payload[:alt_text] = alt_text if alt_text
    response = connection.post("media", payload)
    handle_response(response)
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
end