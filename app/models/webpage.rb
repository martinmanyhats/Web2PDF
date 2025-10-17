class Webpage < ApplicationRecord
  belongs_to :website
  belongs_to :asset
  has_and_belongs_to_many :asset_urls

  def spider(follow_links: true)
    p "!!! Webpage:spider #{inspect}"
    raise "Webpage:spider missing asset #{inspect}" if asset.nil?
    p ">>>>>> Webpage:spider #{assetid}"

    start_at = Time.now

    extract_info_from_document

    if follow_links
      spiderable_link_elements(Nokogiri::HTML(content)).each { spider_link(it) }
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
    uri = website.canonicalise(link)
    if uri.host != website.host ||
       uri.path.blank? ||
       !(uri.scheme == "http" || uri.scheme == "https") ||
       uri.path.match?(%r{/(mainmenu|reports|sitemap|testing)}) # ||
      # uri.path.match?(/\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|xml|mp3|js|css|rtf|txt)$/i)
      p "!!! Webpage:spider_link skipping #{link}"
      return nil
    end
    p "!!! Webpage:spider_link uri #{uri} from #{assetid}"
    host_path = "#{uri.host}#{uri.path}"
    asset_url = AssetUrl.remap_and_find_by_host_path(host_path)
    linked_asset = asset_url.asset
    p "!!! Webpage:asset #{linked_asset.inspect}"
    if linked_asset.present?
      if linked_asset.content_page?
        raise "Webpage:spider_link content page is not text/html" if content_type != "text/html"
        new_webpage = create_or_update_webpage(linked_asset)
        link_asset_url(asset_url, new_webpage)
        p "!!! asset_url #{asset_url.inspect} .webpages #{asset_url.webpages.inspect}"
      elsif linked_asset.redirect_page?
        p "!!! asset.redirect_url #{linked_asset.redirect_url}"
        raise "Webpage:spider_link missing redirect_url linked_asset #{linked_asset.inspect}" unless linked_asset.redirect_url
        (uri, content_type) = resolve_uri(XXX)
        if website.internal?(linked_asset.redirect_url)
          p "!!! spider_link recursing"
          spider_link(linked_asset.redirect_url, depth + 1)
        end
      else
        p "!!! Webpage:spider_link asset is not a content page #{host_path} assetid #{linked_asset.assetid}"
        link_asset_url(asset_url, self)
        raise "XXX" if linked_asset.assetid == 1308
      end
    else
      # Ignore problems with links in Google Sheets.
      return nil if asset.asset_type == "DOL Google Sheet viewer"
      raise "Webpage:spider_link missing asset for host_path #{host_path} webpage #{inspect}"
    end
    new_webpage
  end

  def link_asset_url(asset_url, page)
    begin
      asset_url.webpages << page
      asset_url.save!
    rescue ActiveRecord::RecordNotUnique
      p "!!! Webpage:spider_link avoid duplicate"
    end
  end

  def create_or_update_webpage(asset)
    p "!!! Webpage:create_or_update_webpage asset parent #{self.assetid} #{asset.inspect}"
    page = Webpage.find_or_initialize_by(asset_id: asset.id) do |newpage|
      p "========== new Webpage for assetid #{asset.assetid_formatted} from #{assetid_formatted}"
      newpage.website = website
      newpage.status = "unspidered"
      newpage.asset = asset
    end
    Rails.logger.silence do
      page.save!
      p "!!! create_or_update_webpage saved id #{page.id} assetid #{page.assetid_formatted}"
    end
    page
  end

  def extract_info_from_document = extract_info(asset.document)

  def generate(head: head, html_filename: nil, pdf_filename: nil)
    p "!!! generate id #{id} assetid #{assetid} #{html_filename} #{pdf_filename}"
    raise "Webpage:generate unspidered id #{id}" if status == "unspidered"
    raise "Webpage:generate missing head id #{id}" if head.nil?
    html_filename = asset.filename_with_assetid("html") if html_filename.nil?
    File.open(html_filename, "wb") do |file|
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
      Browser.instance.html_to_pdf(basename: asset.filename_base, html_filename: html_filename, pdf_filename: pdf_filename)
      return
    end
    raise "Webpage:generate unable to create #{filename}"
  end

  def title = asset.title

  def assetid = asset.assetid

  def assetid_formatted = asset.assetid_formatted

  private

  def extract_info(doc)
    p "!!! extract_info assetid #{assetid}"
    self.squiz_canonical_url = doc.css("link[rel=canonical]").first["href"]
    timestamp = doc.css("meta[name='squiz-updated_iso8601']").first&.attribute("content")&.value
    self.squiz_updated = DateTime.iso8601(timestamp) unless timestamp.blank?
    self.content =  doc.css("#main-content")&.inner_html
  end

  def generate_html_links(parsed_content)
    spiderable_link_elements(parsed_content).each do
      it.attributes["href"].value = generate_html_link(clean_link(it))
    end
  end

  def generate_html_link(url)
    p "!!! generate_html_link url #{url.inspect}"
    return "" if url.blank? # Faulty links in content.
    uri = website.canonicalise(url)
    asset = Asset.asset_for_uri(uri)
    p "!!! generate_html_link uri #{uri} asset #{asset.inspect}"
    return url if asset.nil?
    if asset.redirect_url
      p "!!! generate_html_link redirect #{asset.redirect_url}"
      # Spidering has already recursively resolved redirects, but it may be external.
      # TODO spider resolution needs to result in host path
      p "!!! website.canonicalise(asset.redirect_url).host #{website.canonicalise(asset.redirect_url).host}"
      # Do nothing if external URL.
      return asset.redirect_url if website.canonicalise(asset.redirect_url).host != website.host
      return generate_html_link(asset.redirect_url)
    elsif asset.content_page?
      dest_page = Webpage.find_by(asset_id: asset.id)
      raise "Webpage:generate_html_link cannot find dest_page assetid #{assetid} link #{link} uri #{uri}" unless dest_page
      p "!!! internally linking to #{uri.to_s} #{dest_page.title}"
      # asset_url = Asset.asset_url_for_uri(uri)
      # asset_url.webpage = self
      # asset_url.save!
      return "#{website.web_root}/page/#{dest_page.asset.filename_base}.pdf"
    elsif asset.pdf?
      website.add_pdf(asset)
      return "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}"
    elsif asset.image?
      website.add_image(asset)
      return "#{website.web_root}/image/#{assetid_formatted}-#{asset.name}"
    elsif asset.office?
      website.add_office(asset)
      return "#{website.web_root}/pdf/#{assetid_formatted}-#{asset.name}.pdf"
    else
      p ">>>>>>>>>> IGNORING url #{url}"
      website.log(:ignored_links, "assetid #{assetid} url #{url}")
      return url
    end
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

  def spiderable_link_elements(parsed_content)
    # Skip anchors and links with same page.
    parsed_content.css("a[href]")
                  .select { |a| !a["href"].start_with?("#") }
                  .compact
                  .map { clean_link(it) }
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

  def home_page?
    assetid == Asset::HOME_SQUIZ_ASSETID
  end

  def page_not_found_page?
    assetid == Asset::PAGE_NOT_FOUND_SQUIZ_ASSETID
  end
end
