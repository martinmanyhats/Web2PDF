class Webpage < ApplicationRecord
  belongs_to :website
  belongs_to :parent, class_name: "Webpage", optional: true
  has_many :children, class_name: "Webpage", foreign_key: :parent_id, dependent: :destroy

  PAGE_NOT_FOUND_SQUIZ_ASSETID = "13267"

  def self.get_body(url)
    p "!!! Webpage::get_body url #{url}"
    response = HTTParty.get(url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    # TODO: error checking, retry
    p "!!! Webpage::get_body headers #{response.headers}"
    response.body
  end

  def self.local_html?(site_url, url)
    # p "!!! Webpage::local_html? url #{url}"
    max_redirect = 5
    loop do
      # p "!!! Webpage::local_html? url #{url}"
      headers = HTTParty.head(url, {
        follow_redirects: false,
        headers: {
          "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
        },
      })
      if headers.response.is_a?(Net::HTTPSuccess)
        return headers["content-type"].starts_with?("text/html")
      elsif headers.response.is_a?(Net::HTTPRedirection)
        # p "!!! redirection"
        return false unless headers["location"].starts_with?(site_url)
        url = headers["location"]
      elsif headers.response.is_a?(Net::HTTPClientError)
        return false
      end
      max_redirect -= 1
      break if max_redirect < 0
    end
    raise "Webpage::local_html? Too many redirects for #{url}"
  end

  def scrape(force: false, follow_links: true)
    p ">>>>>> Webpage::scrape #{status} url #{url.inspect}"
    raise "Webpage:scrape not unscraped #{inspect}" unless status == "unscraped"
    start_at = Time.now
    body = Webpage::get_body(url)
    self.scrape_duration = (Time.now - start_at).seconds

    # TODO: encoding?
    document = Nokogiri::HTML(body)

    # new_checksum = Digest::SHA256.hexdigest(body)
    # return if new_checksum == @checksum && !force

    false && File.open("tmp/body.html", "wb") do |file|
      file.write(body)
      file.close
    end

    meta_assetid = document.css("meta[name='squiz-assetid']").first
    p "!!! meta_assetid #{meta_assetid}"
    if meta_assetid
      assetid = meta_assetid.attribute("content").value
      if Webpage.where(squiz_assetid: assetid).exists?
        p "!!! duplicate assetid #{assetid}"
        raise "Webpage:scrape duplicate assetid #{assetid} but not scraped" if status != "scraped"
        return
      else
        self.squiz_assetid = assetid
        self.squiz_canonical_url = document.css("link[rel=canonical]").first["href"]
        self.squiz_short_name = document.css("meta[name='squiz-short_name']").first.attribute("content").value
        self.squiz_updated = DateTime.iso8601(document.css("meta[name='squiz-updated_iso8601']").first.attribute("content").value)
        # self.squiz_breadcrumbs = document.css("#breadcrumbs").first&.inner_html
        p "====== squiz_assetid #{squiz_assetid} squiz_short_name #{squiz_short_name} squiz_updated #{squiz_updated}"
      end
    else
      p "!!! Webpage::scrape missing meta squiz-assetid for #{url}"
      self.status = "scraped"
      save!
      return
    end

    if squiz_short_name.blank?
      page_title = document.css("#page-title").first&.text
      self.title = page_title.blank? ? "--" : page_title
    else
      self.title = squiz_short_name
    end

    spider(document) if follow_links

    # self.content = document.css("#main-content-wrapper").to_html
    self.status = "scraped"
    save!
  end

  def generate_html(stream)
    p "!!! Webpage::generate_html id #{id}"
    raise "Webpage::generate_html not scraped id #{id}" if status != "scraped"
    body = Nokogiri::HTML("<div id='webpage-page-#{"%04d" % id}'>#{header_html}</div>")
    process_links(body)
    process_images(body)
    stream.write(body)
  end

  def canon(s)
    canonicalise(s)
  end

  private

  def spider(document)
    p "!!! Webpage:spider url #{url}"
    raise "Webpage:spider already scraped #{inspect}" if status == "scraped"
    website_host = Addressable::URI.parse(website.url).host
    extract_links(document).each do |link|
      p "!!! Webpage::spider link #{link} from #{squiz_assetid} (#{title})"
      next if link == "http://"  # HACK for DH content error.
      if link.include?("./?a=")
        raise "Webpage::spider: link not interpolated: #{link} in Squiz assetid #{squiz_assetid} (#{squiz_short_name}) #{squiz_canonical_url}"
      end
      uri = Addressable::URI.parse(link)
      uri = canonicalise(uri)
      p "!!! uri.scheme #{uri.scheme} uri.host #{uri.host} uri.path #{uri.path}"
      if uri.host != website_host
        p "~~~~~~ not this website"
        next
      end
      if uri.path.blank?
        p "~~~~~~ blank path"
        next
      end
      next unless uri.scheme == "http" || uri.scheme == "https"
      next if uri.path.match?(%r{/(mainmenu|reports)\/})
      if uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
        p "~~~~~~ skipping due to suffix uri.path #{uri.path}"
        next
      end
      # Distinguish pages by assetid as there may be multiple URLs for each.
      assetid = get_squiz_assetid_for_uri(uri)
      raise "Webpage:spider missing assetid #{uri}" unless assetid
      Webpage.find_or_initialize_by(squiz_assetid: assetid) do |page|
        p "!!!!!!!!!! new page assetid #{assetid} uri #{uri.to_s}"
        page.website = website
        page.parent = self
        page.page_path = "#{parent.page_path}.#{"%04d" % id}"
        page.status = "unscraped"
        page.save!
      end
    end
  end

  def process_links(document)
    document.css("a").map.each do |link|
      href = link["href"]
      next if href.blank?
      next if href == "http://"  # HACK for DH content error.
      dest_url = canonicalise(href).to_s
      p "!!! dest_url #{dest_url.inspect}"
      dest_page = Webpage.where(url: dest_url)&.first
      if dest_page && website.url_internal?(dest_url)
        link["href"] = "#webpage-page-#{"%04d" % dest_page.id}"
        p "!!! internally linking #{dest_page.url} to #{link["href"]}"
        # TODO anchors
      end
    end
  end

  def process_images(document)
    document.css("img").map.each do |image|
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

  def process_pdfs(document)
    document.css("a").map.each do |image|
      if File.extname(image.attributes["href"].value) == ".pdf"
        p "!!! PDF #{image.attributes["href"].value}"
      end
    end
  end

  def canonicalise(string_or_uri)
    # p "!!! canonicalise #{string_or_uri.inspect}"
    uri = string_or_uri.kind_of?(Addressable::URI) ? string_or_uri : Addressable::URI.parse(string_or_uri.strip)
    return uri if uri.scheme == "mailto"
    website_host = Addressable::URI.parse(website.url).host
    if uri.host.blank?
      uri.host = website_host
    end
    if uri.host == website_host
      if uri.scheme == "http"
        uri.scheme = "https"
      end
      if uri.path&.ends_with?("/")
        uri.path = uri.path.chop
      end
    end
    if uri.scheme.blank?
      uri.scheme = "https"
    end
    uri.fragment = nil
    uri.query = nil
    uri
  end

  def extract_links
    document(url).css("a").map { |a| a.attribute("href").to_s.strip }
  end

  def get_squiz_assetid_for_uri(a_uri)
    document(a_uri).css("meta[name='squiz-assetid']").first&.attribute("content")&.value
  end

  def document(a_uri)
    Nokogiri::HTML(body(a_uri))
  end

  def body(a_uri)
    p "!!! Webpage::body url #{a_uri.to_s}"
    response = HTTParty.get(a_url.to_s, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    # TODO: error checking, retry
    p "!!! Webpage::body headers #{response.headers}"
    response.body
  end

  def header_html
    html_title = "<span class='webpage-title'>#{title}</span>"
    html_breadcrumbs = "<span class='webpage-breadcrumbs'>#{breadcrumbs_html}</span>"
    "<div class='webpage-header'>#{html_title}#{html_breadcrumbs}</div>#{content}#{timestamp_html}"
  end

  def timestamp_html
    asset_link = "<a href='#{website.url}?a=#{squiz_assetid}'>#{squiz_assetid}</a>"
    "<div class='webpage-timestamp'>Last updated #{self.squiz_updated}, asset #{asset_link}</div>"
  end

  def breadcrumbs_html
    p "!!! breadcrumbs_html #{squiz_breadcrumbs}"
    crumbs = Nokogiri::HTML(squiz_breadcrumbs).css("a").map do |crumb|
      p "!!! CRUMB #{crumb["href"]}-#{crumb.text.strip}"
      "<span class='webpage-breadcrumb'><a href='#{crumb["href"]}'>#{crumb.text.strip}</a></span>"
    end
    crumbs.join("\n")
  end

  def is_page_not_found?
    squiz_assetid == PAGE_NOT_FOUND_SQUIZ_ASSETID
  end
end
