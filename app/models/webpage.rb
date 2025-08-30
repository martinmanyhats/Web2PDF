class Webpage < ApplicationRecord
  belongs_to :website
  # belongs_to :parent, class_name: "Webpage", optional: true
  # has_many :children, class_name: "Webpage", foreign_key: :parent_id, dependent: :destroy

  PAGE_NOT_FOUND_SQUIZ_ASSETID = "13267"

  def self.XXlocal_html?(site_url, url)
    # p "!!! Webpage:local_html? url #{url}"
    max_redirect = 5
    loop do
      # p "!!! Webpage:local_html? url #{url}"
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
    raise "Webpage:local_html? Too many redirects for #{url}"
  end

  def scrape(follow_links: true)
    raise "Webpage:scrape not unscraped #{inspect}" unless status == "unscraped"
    raise "Webpage:scrape missing squiz_assetid #{inspect}" unless squiz_assetid
    raise "Webpage:scrape missing squiz_canonical_url #{inspect}" unless squiz_canonical_url
    p ">>>>>> Webpage:scrape #{status} squiz_canonical_url #{squiz_canonical_url}"
    start_at = Time.now

    p "====== squiz_assetid #{squiz_assetid} squiz_canonical_url #{squiz_canonical_url}"
    extract_squiz

    if follow_links
      extract_links.each do |link|
        p "!!! Webpage:scrape link #{link} from #{squiz_assetid} (#{title})"
        if link.include?("./?a=")
          raise "Webpage:scrape: link not interpolated: #{link} in Squiz assetid #{squiz_assetid} (#{squiz_short_name}) #{squiz_canonical_url}"
        end
        if useful_webpage_link?(link)
          create_webpage_for_url(link)
        else

        end
      end
    end

    false && if squiz_short_name.blank?
      page_title = document.css("#newpage-title").first&.text
      self.title = page_title.blank? ? "--" : page_title
    else
      self.title = squiz_short_name
    end

    self.scrape_duration = (Time.now - start_at).seconds
    self.status = "scraped"
    p "!!! scrape save #{squiz_assetid}"
    Rails.logger.silence do
      save!
    end
  end

  def create_webpage_for_url(a_url)
    p "!!! Webpage:create_webpage_for_url a_url #{a_url}"
    doc = document_for_url(a_url)
    assetid = doc.css("meta[name='squiz-assetid']").first&.attribute("content")&.value&.to_i
    if assetid
      webpage = Webpage.find_or_initialize_by(squiz_assetid: assetid) do |newpage|
        p "!!!!!!!!!! new Webpage assetid #{assetid}"
        newpage.website = website
        newpage.asset_path = "#{asset_path}/#{"%06d" % assetid}"
        newpage.status = "unscraped"
      end
      p "!!! create_webpage_for_url save #{assetid} #{a_url}"
      Rails.logger.silence do
        webpage.save!
      end
    end
  end

  def extract_squiz
    p "!!! extract_squiz #{squiz_assetid}"
    self.squiz_canonical_url = document.css("link[rel=canonical]").first["href"]
    self.squiz_short_name = document.css("meta[name='squiz-short_name']").first&.attribute("content")&.value
    self.squiz_updated = DateTime.iso8601(document.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value)
    self.title = document.css("#newpage-title").first&.text
    self.content =  document.css("#main-content-wrapper")&.inner_html
  end

  def generate_html(head)
    raise "Webpage:generate_html not scraped id #{id}" if status != "scraped"
    filename = generated_filename("html")
    File.open(filename, "wb") do |file|
      file.write("<html>\n#{head}\n<body>\n")
      parsed_content = Nokogiri::HTML(content)
      process_links(parsed_content)
      # process_images(parsed_content)
      file.write("<div id='webpage-#{"%06d" % squiz_assetid}'>#{header_html}#{parsed_content.to_html}</div>")
      file.write("</body>\n</html>\n")
      file.close
      return filename
    end
    raise "Webpage:generate_html unable to create #{filename}"
  end

  def generated_filename(suffix, assetid = squiz_assetid) = "/tmp/dh/#{generated_filename_base(assetid)}.#{suffix}"

  def generated_filename_base(assetid = squiz_assetid) = "art-#{"%06d" % assetid}"

  private

  def process_links(parsed_content)
    parsed_content.css("a").each do |element|
      next if element["href"].blank?
      uri = canonicalise(element["href"])
      case linked_type(uri)
      when "webpage"
        dest_page = Webpage.find_sole_by(squiz_canonical_url: uri.to_s)
        p "!!! internally linking to #{uri.to_s} {#{dest_page.squiz_short_name}"
        element.attributes["href"].value = "#{website.webroot}/#{generated_filename_base(dest_page.squiz_assetid)}.pdf"
      when "pdf"
        p "!!! PDF"
        website.add_pdf_uri(uri)
      when "image"
        p "!!! IMAGE"
      else
        p "!!! ignore #{uri.to_s}"
        next
      end
      # TODO anchors
    end
  end

  def process_images(body)
    parsed_content.css("img").map.each do |image|
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

  def canonicalise(string_or_uri)
    p "!!! canonicalise #{string_or_uri.inspect}"
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
    document.css("a").map { |a| a.attribute("href").to_s.strip }.compact
  end

  def linked_type(uri)
    p "!!! linked_type #{uri}"
    raise "Webpage:linked_type uri http://" if uri.to_s == "http://"  # HACK for DH content error.
    if uri.host != website.host
      p "~~~~~~ offsite"
      return "offsite"
    end
    if uri.path.blank?
      p "~~~~~~ blank path"
      return nil
    end
    return nil unless uri.scheme == "http" || uri.scheme == "https"
    return nil if uri.path.match?(%r{/(mainmenu|reports)\/})
    return "pdf" if uri.path.match?(/\.pdf$/i)
    return "image" if uri.path.match?(/\.(jpg|jpeg|png|gif)$/i)
    return "webpage" if Webpage.where(squiz_canonical_url: uri.to_s).exists?
    nil
  end

  def XXuseful_webpage_link?(link)
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
    Nokogiri::HTML(website.body(canonicalise(a_url)))
  end

  def header_html
    html_title = "<span class='webpage-title'>#{title.present? ? title : squiz_short_name}</span>"
    html_breadcrumbs = "<span class='webpage-breadcrumbs'>#{breadcrumbs_html}</span>"
    "<div class='webpage-header'>#{html_title}#{html_breadcrumbs}</div>"
  end

  def breadcrumbs_html
    # p "!!! breadcrumbs_html #{squiz_breadcrumbs}"
    crumbs = Nokogiri::HTML(squiz_breadcrumbs).css("a").map do |crumb|
      "<span class='webpage-breadcrumb'><a href='#{crumb["href"]}'>#{crumb.text.strip}</a></span>"
    end
    crumbs.join("\n")
  end

  def is_page_not_found?
    squiz_assetid == PAGE_NOT_FOUND_SQUIZ_ASSETID
  end
end
