class Webpage < ApplicationRecord
  belongs_to :website
  belongs_to :asset

  PAGE_NOT_FOUND_SQUIZ_ASSETID = "13267"

  def self.XXlocal_html?(site_url, url)
    # p "!!! Webpage:local_html? url #{url}"
    max_redirect = 5
    loop do
      # p "!!! Webpage:local_html? url #{url}"
      headers = HTTParty.head(url, {
        follow_redirects: false,
        headers: Website.http_headers,
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

  def spider(follow_links: true)
    p "!!! Webpage:spider #{inspect}"
    raise "Webpage:spider not unspidered #{inspect}" unless status == "unspidered"
    raise "Webpage:spider missing asset #{inspect}" if asset.nil?
    p ">>>>>> Webpage:spider #{asset.assetid}"

    start_at = Time.now
    url = asset.asset_urls.first.url

    extract_info(asset.document)

    if follow_links
      spiderable_links(Nokogiri::HTML(content)).each do |link|
        p "+++++ link #{link}"
        raise "Webpage:spider link not interpolated #{link} in assetid #{asset.assetid} (#{squiz_short_name}) #{squiz_canonical_url}" if link.include?("./?a=")
        uri = canonicalise(link)
        next if uri.host != website.host
        next if uri.path.blank?
        next unless uri.scheme == "http" || uri.scheme == "https"
        next if uri.path.match?(%r{/(mainmenu|reports|sitemap|sitearchive|testing)})
        next if uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
        p "!!! Webpage:spider uri #{uri.host}#{uri.path} from #{asset.assetid}"
        host_path = "#{uri.host}#{uri.path}"
        linked_asset = Asset.asset_for_url(host_path)
        p "!!! Webpage:asset #{linked_asset.inspect}"
        if linked_asset.present?
          if linked_asset.content_page?
            create_webpage(linked_asset)
          elsif linked_asset.redirection?
            p "!!! Webpage:spider redirection #{host_path}"
            if website.internal?(url) && (linked_asset = Asset.asset_for_redirection(uri))
              create_webpage(linked_asset)
            end
          else
            p "!!! Webpage:spider asset is not a page #{host_path}"
          end
        else
          # Ignore problems with links in Google Sheets.
          next if asset.asset_type == "DOL Google Sheet viewer"
          raise "Webpage:spider missing asset for #{host_path} webpage #{inspect}"
        end
      end
    end

    false && if squiz_short_name.blank?
      page_title = asset.document.css("#newpage-title").first&.text
      self.title = page_title.blank? ? "--" : page_title
    else
      self.title = squiz_short_name
    end

    self.spider_duration = (Time.now - start_at).seconds
    self.status = "spidered"
    p "!!! Webpage:spider save #{asset.assetid}"
    Rails.logger.silence do
      save!
    end
  end

  def create_webpage(asset)
    p "!!! Webpage:create_webpage asset #{asset.inspect}"
    webpage = Webpage.find_or_initialize_by(asset_id: asset.id) do |newpage|
      p "========== new Webpage assetid #{asset.assetid}"
      newpage.website = website
      newpage.asset_path = "#{asset_path}/#{"%06d" % asset.assetid}"
      newpage.status = "unspidered"
      newpage.asset = asset
      p "!!! create_webpage save #{asset.assetid}"
      Rails.logger.silence do
        newpage.save!
      end
    end
  end

  def extract_info_from_document
    extract_info(asset.document)
  end

  def generate_html(head)
    raise "Webpage:generate_html not spidered id #{id}" if status != "spidered"
    filename = generated_filename("html")
    File.open(filename, "wb") do |file|
      file.write("<html>\n#{head}\n<content_for_url>\n")
      parsed_content = Nokogiri::HTML(content)
      process_links(parsed_content)
      # process_images(parsed_content)
      file.write("<div id='webpage-#{"%06d" % asset.assetid}'>#{header_html}#{parsed_content.to_html}</div>")
      file.write("</content_for_url>\n</html>\n")
      file.close
      return filename
    end
    raise "Webpage:generate_html unable to create #{filename}"
  end

  def generated_filename(suffix, assetid = asset.assetid) = "/tmp/dh/#{suffix}/#{generated_filename_base(assetid)}.#{suffix}"

  def generated_filename_base(assetid = asset.assetid) = "art-#{"%06d" % assetid}"

  def XXdocument_for_url(a_url)
    p "!!! document_for_url #{a_url}"
    Nokogiri::HTML(website.content_for_url(canonicalise(a_url)))
  end

  private

  def extract_info(doc)
    p "!!! extract_info assetid #{asset.assetid}"
    self.squiz_canonical_url = doc.css("link[rel=canonical]").first["href"]
    self.squiz_short_name = doc.css("meta[name='squiz-short_name']").first&.attribute("content")&.value
    self.squiz_updated = DateTime.iso8601(doc.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value)
    self.title = doc.css("#newpage-title").first&.text
    self.content =  doc.css("#main-content")&.inner_html
  end

  def process_links(parsed_content)
    spiderable_links(parsed_content).each do |link|
      next if link.blank? # Faulty links in content.
      uri = canonicalise(link)
      case linked_type(uri)
      when "webpage"
        p "!!! webpage uri #{uri}"
        dest_page = Webpage.find_by(squiz_canonical_url: uri.to_s)
        raise "Webpage:process_links cannot find #{uri.to_s}" unless dest_page
        p "!!! internally linking to #{uri.to_s} {#{dest_page.squiz_short_name}"
        element.attributes["href"].value = "#{website.webroot}/#{generated_filename_base(dest_page.squiz_assetid)}.pdf"
      when "pdf"
        website.add_pdf_uri(uri)
      when "image"
        website.add_image_uri(uri)
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

  def canonicalise(url_or_uri)
    # p "!!! canonicalise #{url_or_uri.inspect}"
    uri = if url_or_uri.kind_of?(String)
            url_or_uri = url_or_uri.strip
            url_or_uri = "https://#{url_or_uri}" unless url_or_uri =~ /^https?:\/\//
            Addressable::URI.parse(url_or_uri)
          else
            url_or_uri
    end
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
    # p "!!! canonicalise result #{uri.inspect}"
    uri
  end

  def spiderable_links(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("a[href]")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
                  .map { |element| clean_link(element) }
  end

  def clean_link(element)
    # TODO remove anchor?
    element.attribute("href").to_s.strip
  end

  def linked_type(url)
    p "!!! linked_type url #{url}"
    uri = canonicalise(url)
    raise "Webpage:linked_type url http://" if uri.to_s == "http://" # Due to empty link
    ltype = begin
              if uri.path.blank? || !(uri.scheme == "http" || uri.scheme == "https") || uri.path.match?(%r{/(mainmenu|reports)\/})
                nil
              elsif uri.host != website.host
                "offsite"
              elsif uri.path.match?(/\.pdf$/i)
                "pdf"
              elsif uri.path.match?(/\.(jpg|jpeg|png|gif)$/i)
                "image"
              else
                # Might be a redirect.
                if new_url = resolve_redirection(url)
                  p "!!! new url #{new_url}"
                  linked_type(new_url)
                else
                  "webpage"
                end
              end
            end
    p "!!! linked_type ltype #{ltype}"
    ltype
  end

  def resolve_redirection(url)
    p "!!! resolve_redirection? #{url}"
    depth = 0
    loop do
      asset = Asset.asset_for_redirection(URI.parse(url))
      url = asset.asset_urls.first
      return url if asset.asset_type != "Redirect Page"
      depth += 1
      raise "Webpage:resolve_redirection redirect depth exceeded" if depth > 5
    end
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
