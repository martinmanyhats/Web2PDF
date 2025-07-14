class Webpage < ApplicationRecord
  belongs_to :website
  has_many :weblinks, foreign_key: "from_id",dependent: :delete_all

  def scrape(force: false)
    p "!!! Webpage::scrape url #{url}"
    start_at = Time.now
    body = get_body(url)
    new_checksum = Digest::SHA256.hexdigest(body)
    return "existing" if new_checksum == @checksum && !force

    File.open("tmp/body.html", "wb") do |file|
      file.write(body)
      file.close
    end

    self.scrape_duration = (Time.now - start_at).seconds
    # TODO: encoding?
    document = Nokogiri::HTML(body)

    page_title = document.css("#page-title")&.first.text
    self.title = page_title.blank? ? "--" : page_title
    self.canonical_url = document.css("link[rel=canonical]").first["href"]
    self.content = document.css("#main-content-wrapper").to_html

    # Find other pages on this website and record links.
    website_host = URI(website.url).host
    extract_links(document).each do |link|
      p "!!! link #{link}"
      uri = canonicalise(URI(link))
      next unless uri.scheme == "http" || uri.scheme == "https"
      next if uri.path.blank?
      host = uri.host
      next if uri.path.starts_with?("/mainmenu/")
      next if host != website_host
      file_suffix = File.extname(uri.path)
      next if file_suffix.present? && file_suffix != ".html"
      linkurl = uri.to_s
      p "!!! from #{url} to #{linkurl}"
      to_webpage = Webpage.find_or_initialize_by(url: linkurl) do |page|
        page.website = website
        page.status = "unscraped"
        page.save!
      end
      p "!!! to_webpage #{to_webpage.inspect}"
=begin
      Weblink.find_or_initialize_by(from: self, to: to_webpage) do |link|
        link.from = self
        link.to = to_webpage
        link.linktype = "a"
        link.linkvalue = linkurl
        link.save!
        p "!!! new link: #{link.inspect}"
      end
=end
    end
    self.status = "scraped"
    p "!!! Webpage::scraped #{inspect} content #{content.truncate(40)}"
    save!
    "new"
  end

  def generate_html(stream)
    p "!!! Webpage::generate_html id #{id}"
    raise "Webpage::generate_html not scraped" if status != "scraped"
    body = Nokogiri::HTML("<div id='_internal-page-#{"%04d" % id}'><div>PAGE #{id} #{title}</div>#{content}#{timestamp_html}</div>")
    process_links(body)
    process_images(body)
    stream.write(body)
  end

  def XXgenerate_pdf
    p "============================ Webpage::generate_pdf #{inspect}"
    body = Nokogiri::HTML("<body>#{content}</body>")
    # XXprocess_scripts(document)
    process_links(body)
    process_images(body)
    File.open("tmp/generate.html", "wb") do |file|
      file.write(body.to_html)
      file.close
    end
    body.css("body")[0]["id"] = "_internal-page-#{"%04d" % id}"
    body.css("body")[0].add_child(timestamp_html)
    File.open("tmp/page-#{"%04d" % id}.html", "wb") do |file|
      file.write(body.to_html)
      file.close
    end
    pdf = FerrumPdf.render_pdf(html: body.to_html,
                               pdf_options: {
                                 landscape: true,
                                 format: :A4,
                               } )
    # pdf = Grover.new(body.to_html, format: "A4").to_pdf
    # pdf = WickedPdf.new.pdf_from_string(body.to_html)
    pdf_filename = "tmp/page-#{"%04d" % id}.pdf"
    File.open(pdf_filename, "wb") do |file|
      file.write(pdf)
      file.close
    end
    pdf_filename
  end

  private

  def XXprocess_scripts(document)
    document.css("script").map do |script|
      if script.attribute("src")&.value&.include?("dol-cookie-control.js")
        script.replace("<!- dol-cookie-control.js ->")
      end
    end
  end

  def process_links(document)
    document.css("a").map.each do |link|
      dest_url = canonicalise(link["href"]).to_s
      p "!!! dest_url #{dest_url.inspect}"
      dest_page = Webpage.where(url: dest_url)&.first
      if dest_page && website.url_internal?(dest_url)
        link["href"] = "#_internal-page-#{"%04d" % dest_page.id}"
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
    uri = string_or_uri.kind_of?(URI) ? string_or_uri : URI.parse(string_or_uri.strip)
    return uri if uri.opaque
    if uri.host.blank?
      uri.host = URI(website.url).host.to_s
    end
    if uri.host == URI(website.url).host
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
    if uri.host.blank?
      uri.host = URI(website.url).host
    end
    p "!!! canonicalise uri #{uri.to_s}"
    uri
  end

  def extract_links(document)
    p "!!! extract_links size #{document.css("a").size}"
    p "!!! extract_links #{document.css("a").map { |a| a.attribute("href") }}"
    document.css("a").map { |a| a.attribute("href").to_s.strip }
  end

  def timestamp_html
    "<div style='font-size:60%;color:#444'>Captured #{Time.now} #{id}</div>"
  end

  def get_body(url)
    p "!!! Webpage::get_body url #{url}"
    response = HTTParty.get(url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    # TODO: error checking, retry
    p "!!! Webpage::get_body body #{response.body.truncate(2000)}"
    response.body
  end
end
