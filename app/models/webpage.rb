class Webpage < ApplicationRecord
  belongs_to :website
  # belongs_to :parent, class_name: "Webpage", optional: true
  # has_many :children, class_name: "Webpage", foreign_key: :parent_id, dependent: :destroy

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
    raise "Webpage:scrape not unscraped #{inspect}" unless status == "unscraped"
    raise "Webpage:scrape missing squiz_assetid #{inspect}" unless squiz_assetid
    raise "Webpage:scrape missing squiz_canonical_url #{inspect}" unless squiz_canonical_url
    p ">>>>>> Webpage::scrape #{status} squiz_canonical_url #{squiz_canonical_url}"
    start_at = Time.now

    # new_checksum = Digest::SHA256.hexdigest(body)
    # return if new_checksum == @checksum && !force

    # self.squiz_canonical_url = document.css("link[rel=canonical]").first["href"]
    # self.squiz_short_name = document.css("squiz[name='squiz-short_name']").first.attribute("content").value
    # self.squiz_updated = DateTime.iso8601(document.css("squiz[name='squiz-updated_iso8601']").first.attribute("content").value)
    # self.squiz_breadcrumbs = document.css("#breadcrumbs").first&.inner_html
    p "====== squiz_assetid #{squiz_assetid} squiz_canonical_url #{squiz_canonical_url}"

    spider if follow_links

    false && if squiz_short_name.blank?
      page_title = document.css("#newpage-title").first&.text
      self.title = page_title.blank? ? "--" : page_title
    else
      self.title = squiz_short_name
    end

    self.scrape_duration = (Time.now - start_at).seconds
    self.status = "scraped"
    save!
  end

  def create_webpage_for_url(a_url)
    p "!!! Webpage::create_webpage_for_url a_url #{a_url}"
    doc = document_for_url(a_url)
    assetid = doc.css("meta[name='squiz-assetid']").first&.attribute("content")&.value&.to_i
    if assetid
      Webpage.find_or_initialize_by(squiz_assetid: assetid) do |newpage|
        p "!!!!!!!!!! new Webpage assetid #{assetid}"
        newpage.website = website
        # newpage.parent = self
        newpage.asset_path = "#{asset_path}/#{"%06d" % assetid}"
        newpage.status = "unscraped"
        newpage.squiz_canonical_url = doc.css("link[rel=canonical]").first["href"]
        newpage.squiz_short_name = doc.css("meta[name='squiz-short_name']").first&.attribute("content")&.value
        newpage.squiz_updated = DateTime.iso8601(doc.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value)
        newpage.title = doc.css("#newpage-title").first&.text
        newpage.content =  doc.css("#main-content-wrapper")&.inner_html
        p "!!! newpage save #{newpage.inspect}"
        Rails.logger.silence do
          newpage.save!
        end
      end
    else
      p "!!! create_webpage_for_url not a Squiz webpage uri #{a_url}"
    end
  end

  def generate_html(stream)
    p "!!! Webpage::generate_html id #{id}"
    raise "Webpage::generate_html not scraped id #{id}" if status != "scraped"
    body = Nokogiri::HTML("<div id='webpage-#{"%06d" % squiz_assetid}'>#{header_html}#{content}</div>")
    process_links(body)
    process_images(body)
    stream.write(body)
  end

  private

  def spider
    p "!!! Webpage:spider url #{squiz_canonical_url}"
    raise "Webpage:spider already scraped #{inspect}" if status == "scraped"
    website_host = Addressable::URI.parse(website.url).host
    extract_links.each do |link|
      p "!!! Webpage::spider link #{link} from #{squiz_assetid} (#{title})"
      if link.include?("./?a=")
        raise "Webpage::spider: link not interpolated: #{link} in Squiz assetid #{squiz_assetid} (#{squiz_short_name}) #{squiz_canonical_url}"
      end
=begin
      next if link == "http://"  # HACK for DH content error.
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
=end
      create_webpage_for_url(link) if useful_webpage_link?(link)
    end
  end

  def process_links(body)
    body.css("a").map.each do |link|
      href = link["href"]
      next unless useful_webpage_link?(href)
      dest_url = canonicalise(href).to_s
      # p "!!! dest_url #{dest_url.inspect}"
      dest_page = Webpage.where(squiz_canonical_url: dest_url)&.first
      if dest_page
        p "!!! internally linking #{href} to #{dest_url} {#{dest_page.squiz_short_name}"
        link["href"] = "#webpage-#{"%06d" % dest_page.squiz_assetid}" # TODO fix for file per webpage
      else
        # Not actually an internal webpage.
        # p "!!! not internal #{href}"
      end
      # TODO anchors
    end
  end

  def process_images(body)
    body.css("img").map.each do |image|
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

  def process_pdfs(body)
    body.css("a").map.each do |image|
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
    p "!!! extracting links content #{content&.truncate(1000)}"
    document.css("a").map { |a| a.attribute("href").to_s.strip }
    # Nokogiri(content).map { |a| a.attribute("href").to_s.strip }
  end

  def useful_webpage_link?(link)
    # p "!!! useful_webpage_link? #{link}"
    return false if link.blank? || link == "http://"  # HACK for DH content errora.
    uri = Addressable::URI.parse(link)
    uri = canonicalise(uri)
    # p "!!! useful_webpage_link? uri.scheme #{uri.scheme} uri.host #{uri.host} uri.path #{uri.path}"
    if uri.host != website.host
      # p "~~~~~~ not this website"
      return false
    end
    if uri.path.blank?
      # p "~~~~~~ blank path"
      return false
    end
    return false unless uri.scheme == "http" || uri.scheme == "https"
    return false if uri.path.match?(%r{/(mainmenu|reports)\/})
    if uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
      # p "~~~~~~ skipping due to suffix uri.path #{uri.path}"
      return false
    end
    true
  end

  def document
    @_document ||= document_for_url(squiz_canonical_url)
  end

  def document_for_url(a_url)
    Nokogiri::HTML(body(canonicalise(a_url)))
  end

  def body(a_url)
    p "!!! Webpage::body url #{a_url}"
    response = HTTParty.get(a_url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    # TODO: error checking, retry
    p "!!! Webpage::body headers #{response.headers}"
    response.body
  end

  def header_html
    html_title = "<span class='webpage-title'>#{title.present? ? title : squiz_short_name}</span>"
    html_breadcrumbs = "<span class='webpage-breadcrumbs'>#{breadcrumbs_html}</span>"
    "<div class='webpage-header'>#{html_title}#{html_breadcrumbs}</div>#{content}"
  end

  def XXtimestamp_html
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
