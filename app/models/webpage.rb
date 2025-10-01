class Webpage < ApplicationRecord
  belongs_to :website
  belongs_to :asset
  has_many :webpage_parents

  PAGE_NOT_FOUND_SQUIZ_ASSETID = "13267"

  def spider(follow_links: true)
    p "!!! Webpage:spider #{inspect}"
    raise "Webpage:spider missing asset #{inspect}" if asset.nil?
    p ">>>>>> Webpage:spider #{assetid}"

    start_at = Time.now
    url = asset.url

    extract_info_from_document

    if follow_links
      spiderable_link_elements(Nokogiri::HTML(content)).map { clean_link(it) }.each { spider_link(it) }
    end

    self.spider_duration = (Time.now - start_at).seconds
    self.status = "spidered"
    p "!!! Webpage:spider save #{assetid}"
    Rails.logger.silence do
      save!
    end
  end

  def spider_link(link, depth = 0)
    p "!!! Webpage:spider_link link #{link} depth #{depth}"
    raise "Webpage:spider_link depth exceeded #{link}" if depth > 3
    raise "Webpage:spider_link link not interpolated #{link} in assetid #{assetid} #{squiz_canonical_url}" if link.include?("./?a=")
    uri = canonicalise(link)
    if uri.host != website.host ||
       uri.path.blank? ||
       !(uri.scheme == "http" || uri.scheme == "https") ||
       uri.path.match?(%r{/(mainmenu|reports|sitemap|testing)}) ||
       uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
      p "!!! Webpage:spider_link skipping #{link}"
      return nil
    end
    p "!!! Webpage:spider_link uri #{uri.host}#{uri.path} from #{assetid}"
    host_path = "#{uri.host}#{uri.path}"
    linked_asset = Asset.asset_for_url(host_path)
    p "!!! Webpage:asset #{linked_asset.inspect}"
    if linked_asset.present?
      if linked_asset.content_page?
        new_webpage = create_or_update_webpage(linked_asset)
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
      return nil if asset.asset_type == "DOL Google Sheet viewer"
      raise "Webpage:spider_link missing asset for host_path #{host_path} webpage #{inspect}"
    end
    new_webpage
  end

  def create_or_update_webpage(asset)
    p "!!! Webpage:create_or_update_webpage asset parent #{self.assetid} #{asset.inspect}"
    page = Webpage.find_or_initialize_by(asset_id: asset.id) do |newpage|
      p "========== new Webpage assetid #{assetid_formatted}"
      newpage.website = website
      newpage.status = "unspidered"
      newpage.asset = asset
    end
    p "*** existing webpage_parents #{page.parent_assetids}"
    unless page.webpage_parents.where(webpage: page, parent: self).exists?
      p "*** adding webpage_parent assetid #{self.assetid} to #{page.assetid}"
      new_webpage_parent = WebpageParent.build(webpage: page, parent: self)
      p "!!! new_parent #{new_webpage_parent.inspect}"
      page.webpage_parents << new_webpage_parent
      p "!!! new parents #{page.webpage_parents.inspect}"
      # raise "XX" if page.webpage_parents.count > 1
    else
      p "*** NOT adding webpage_parent assetid to #{self.assetid}"
    end
    p "*** new webpage_parents #{page.parent_assetids}}"
    Rails.logger.silence do
      page.save!
      p "!!! create_or_update_webpage saved id #{page.id} assetid #{page.assetid_formatted} parents #{page.parent_assetids}"
    end
  end

  def parents
    webpage_parents.map(&:parent)
  end

  def parent_assetids
    webpage_parents.map { it.parent.assetid }
  end

  def extract_info_from_document
    extract_info(asset.document)
  end

  def generate(head)
    raise "Webpage:generate not spidered id #{id}" if status != "spidered"
    filename = filename_with_assetid("html")
    File.open(filename, "wb") do |file|
      file.write("<html>\n#{head}\n")
      body = Nokogiri::HTML("<div class='webpage-content'>#{content}</div>").css("body").first
      body["data-assetid"] = assetid_formatted
      body.first_element_child.before(Nokogiri::XML::DocumentFragment.parse(header_html))
      generate_html_links(body)
      generate_external_links(body)
      # generate_images(body)
      file.write(body.to_html)
      file.write("</html>\n")
      file.close
      save!
      Browser.instance.html_to_pdf(basename_with_assetid)
      return
    end
    raise "Webpage:generate unable to create #{filename}"
  end

  def filename_with_assetid(suffix, output_dir = nil)
    output_dir = suffix if output_dir.nil?
    "#{website.file_root}/#{output_dir}/#{basename_with_assetid}.#{suffix}"
  end

  def basename_with_assetid
    base = squiz_canonical_url.gsub(/.*\//, "")
    "#{assetid_formatted}-#{base}"
  end

  def title
    asset.name.present? ? asset.name : asset.short_name
  end

  def assetid = asset.assetid

  def assetid_formatted = asset.assetid_formatted

  private

  def extract_info(doc)
    p "!!! extract_info assetid #{assetid}"
    self.squiz_canonical_url = doc.css("link[rel=canonical]").first["href"]
    self.squiz_updated = DateTime.iso8601(doc.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value)
    self.content =  doc.css("#main-content")&.inner_html
  end

  def generate_html_links(parsed_content)
    spiderable_link_elements(parsed_content).each { generate_html_link(it) }
  end

  def generate_html_link(element)
    p "!!! generate_html_link element #{element.inspect}"
    link = clean_link(element)
    return if link.blank? # Faulty links in content.
    uri = canonicalise(link)
    asset = Asset.asset_for_uri(uri)
    if asset&.redirect_url
      p "!!! generate_html_link redirect #{asset.redirect_url}"
      # Spidering has already recursively resolved redirects.
      asset = Asset.asset_for_url(asset.redirect_url)
    end
    p "!!! generate_html_link uri #{uri} asset #{asset.inspect}"
    return if asset.nil?
    if asset.content_page?
      dest_page = Webpage.find_by(asset_id: asset.id)
      raise "Webpage:generate_html_link cannot find dest_page assetid #{assetid} link #{link} uri #{uri}" unless dest_page
      p "!!! internally linking to #{uri.to_s} #{dest_page.title}"
      element.attributes["href"].value = "#{website.web_root}/page/#{dest_page.asset.filename_base}.pdf"
      return
    end
    if asset.pdf?
      element.attributes["href"].value = "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}"
      website.add_pdf(asset)
    elsif asset.image?
      website.add_image(asset)
    elsif asset.office?
      element.attributes["href"].value = "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}.pdf"
      website.add_office(asset)
    else
      p ">>>>>>>>>> IGNORING uri #{uri} link#{link}"
      website.log(:ignored_links, "assetid #{assetid} link #{link}")
      return
    end
    p "!!! link #{link} uri #{uri}"
    asset_url = Asset.asset_url_for_uri(uri)
    asset_url.webpage = self
    asset_url.save!
    # TODO anchors
  end

  def generate_external_links(parsed_content)
    parsed_content.css("iframe").each do |iframe|
      p "!!! generate_external_links #{iframe["src"].inspect}"
      iframe.add_next_sibling("<p class='iframe-comment'>External URL: <a href='#{iframe["src"]}'>#{iframe["src"]}</a></p>")
    end
  end

  def generate_images(parsed_content)
    p "!!! generate_images"
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

  def spiderable_images(parsed_content)
    parsed_content.css("img").each do |image|
      p "!!! image src #{image["src"]}"
    end
  end

  def spiderable_external_elements(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("iframe")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
  end

  def clean_link(element)
    # TODO remove anchor?
    element.attribute("href").to_s.strip
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
    html_title = "<span class='webpage-title'>#{title}</span>"
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
