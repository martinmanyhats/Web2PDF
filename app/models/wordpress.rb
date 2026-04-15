class Wordpress
  WP_BASE = "https://wpdh.martinreed.co.uk/wp-json/wp/v2"

  def initialize(username:, application_password:)
    p "Wordpress username #{username}"
    @auth_header = "Basic #{Base64.strict_encode64("#{username}:#{application_password}")}"
  end

  def create_page(title:, slug:, content:, status: "publish")
    slug = title unless slug.present?
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

  def upload_media(file_path)
    raise "Wordpress:upload_media file not found #{file_path}" unless File.exist?(file_path)

    file = Faraday::Multipart::FilePart.new(
      file_path,
      mime_type(file_path),
      File.basename(file_path)
    )
    payload = { file: file }
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