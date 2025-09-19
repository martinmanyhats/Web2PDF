class Webpage < ApplicationRecord
  belongs_to :website
  belongs_to :asset

  PAGE_NOT_FOUND_SQUIZ_ASSETID = "13267"

  def spider(follow_links: true)
    p "!!! Webpage:spider #{inspect}"
    raise "Webpage:spider not unspidered #{inspect}" unless status == "unspidered"
    raise "Webpage:spider missing asset #{inspect}" if asset.nil?
    p ">>>>>> Webpage:spider #{asset.assetid}"

    start_at = Time.now
    url = asset.asset_urls.first.url

    extract_info(asset.document)

    if follow_links
      spiderable_link_elements(Nokogiri::HTML(content)).map { clean_link(it) }.each { spider_link(it) }
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

  def spider_link(link, depth = 0)
    p "!!! Webpage:spider_link link #{link}"
    raise "Webpage:spider_link depth exceeded #{link}" if depth > 3
    raise "Webpage:spider_link link not interpolated #{link} in assetid #{asset.assetid} (#{squiz_short_name}) #{squiz_canonical_url}" if link.include?("./?a=")
    uri = canonicalise(link)
    if uri.host != website.host ||
       uri.path.blank? ||
       !(uri.scheme == "http" || uri.scheme == "https") ||
       uri.path.match?(%r{/(mainmenu|reports|sitemap|testing)}) ||
       uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
      p "!!! Webpage:spider_link skipping #{link}"
      return
    end
    false && begin
    return if uri.host != website.host
    return if uri.path.blank?
    return unless uri.scheme == "http" || uri.scheme == "https"
    return if uri.path.match?(%r{/(mainmenu|reports|sitemap|testing)})
    return if uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
    end
    p "!!! Webpage:spider_link uri #{uri.host}#{uri.path} from #{asset.assetid}"
    host_path = "#{uri.host}#{uri.path}"
    linked_asset = Asset.asset_for_url(host_path)
    p "!!! Webpage:asset #{linked_asset.inspect}"
    if linked_asset.present?
      if linked_asset.content_page?
        create_webpage(linked_asset)
      elsif linked_asset.redirect_page?
        p "!!! asset.redirect_url #{linked_asset.redirect_url}"
        raise "Webpage:spider_link missing redirect_url linked_asset #{linked_asset.inspect}" unless linked_asset.redirect_url
        if website.internal?(linked_asset.redirect_url)
          p "!!! spider_link recursing"
          spider_link(linked_asset.redirect_url, depth + 1)
        end
      else
        p "!!! Webpage:spider_link asset is not a content page #{host_path}"
      end
    else
      # Ignore problems with links in Google Sheets.
      return if asset.asset_type == "DOL Google Sheet viewer"
      raise "Webpage:spider_link missing asset for host_path #{host_path} webpage #{inspect}"
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
      file.write("<html>\n#{head}\n")
      body = Nokogiri::HTML(content).css("body").first
      body["data-assetid"] = "%06d" % asset.assetid
      body.first_element_child.before(Nokogiri::XML::DocumentFragment.parse(header_html))
      generate_html_links(body)
      # generate_html_images(body)
      file.write(body.to_html)
      file.write("</html>\n")
      file.close
      return filename
    end
    raise "Webpage:generate_html unable to create #{filename}"
  end

  def generated_filename(suffix, assetid = asset.assetid) = "/tmp/dh/#{suffix}/#{generated_filename_base(assetid)}.#{suffix}"

  def generated_filename_base(assetid = asset.assetid) = "page-#{"%06d" % assetid}"

  private

  def extract_info(doc)
    p "!!! extract_info assetid #{asset.assetid}"
    self.squiz_canonical_url = doc.css("link[rel=canonical]").first["href"]
    self.squiz_short_name = doc.css("meta[name='squiz-short_name']").first&.attribute("content")&.value
    self.squiz_updated = DateTime.iso8601(doc.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value)
    self.title = doc.css("#newpage-title").first&.text
    self.content =  doc.css("#main-content")&.inner_html
  end

  def generate_html_links(parsed_content)
    spiderable_link_elements(parsed_content).each do |element|
      p "!!! generate_html_links #{element.inspect}"
      link = clean_link(element)
      next if link.blank? # Faulty links in content.
      uri = canonicalise(link)
      asset = Asset.asset_for_uri(uri)
      p "!!! generate_html_links asset #{asset.inspect}"
      if asset&.redirect_url
        p "!!! generate_html_links redirect #{asset.redirect_url}"
        # Spidering has already recursively resolved redirects.
        asset = Asset.asset_for_url(asset.redirect_url)
      end
      next if asset.nil?
      if asset.content_page?
        dest_page = Webpage.find_by(asset_id: asset.id)
        raise "Webpage:generate_html_links cannot find dest_page assetid #{asset.assetid} link #{link} uri #{uri}" unless dest_page
        p "!!! internally linking to #{uri.to_s} #{dest_page.squiz_short_name}"
        element.attributes["href"].value = "#{website.webroot}/#{generated_filename_base(dest_page.asset.assetid)}.pdf"
      elsif asset.pdf?
        element.attributes["href"].value = "#{website.webroot}/assets/#{"%06d" % asset.assetid}-#{asset.name}"
        website.add_pdf(asset)
      elsif asset.image?
        website.add_image(asset)
      else
        p ">>>>>>>>>> IGNORING uri #{uri} link#{link}"
        website.log(:ignored_links, "assetid #{asset.assetid} link #{link}")
      end
      # TODO anchors
    end
  end

  def process_images(body)
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

  def spiderable_link_elements(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("a[href]")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
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
