class Webpage < ApplicationRecord
  belongs_to :website
  has_many :weblinks, foreign_key: "from_id",dependent: :delete_all

  def scrape(force: false)
    p "!!! Webpage::scrape url #{url}"
    start_at = Time.now
    body = get_body(url)
    new_checksum = Digest::SHA256.hexdigest(body)
    return "existing" if new_checksum == @checksum && !force

    self.scrape_duration = (Time.now - start_at).seconds
    # TODO: encoding?
    self.body = body
    document = Nokogiri::HTML(body)
    File.open("tmp/body.html", "wb") do |file|
      file.write(document.to_html)
      file.close
    end
    page_title = document.css("#page-title")&.first.text
    self.title = page_title.blank? ? "--" : page_title

    # Remove main menu.
    p "!!! main_menu1 #{document.css("#main-wrapper").inspect}"
    document.css("#menu-wrapper")&.first.remove
    p "!!! main_menu2 #{document.css("#main-wrapper").inspect}"

    # Find and record links to other pages on this website.
    website_host = URI(website.url).host
    extract_links(document).each do |link|
      p "!!! link #{link}"
      uri = canonicalise(URI(link))
      next unless uri.scheme == "http" || uri.scheme == "https"
      next if uri.path.blank?
      host = uri.host
      next if host.present? && host != website_host
      #file_suffix = uri.path.match(/\.(\w+\z)/)[1]
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
      weblink = Weblink.find_or_initialize_by(from: self, to: to_webpage) do |link|
        link.from = self
        link.to = to_webpage
        link.linktype = "a"
        link.linkvalue = linkurl
        link.save!
        p "!!! new link: #{link.inspect}"
      end
    end
    self.status = "scraped"
    p "!!! Webpage::scraped #{inspect} body #{self.body.truncate(40)}"
    save!
    "new"
  end

  def generate_pdf
    p "!!! Webpage::generate_pdf #{inspect}"
    document = Nokogiri::HTML(body)
    document.css("a").map.each do |link|
      p "!!! link1 #{link.inspect}"
      p "!!! link4 #{link["href"].inspect}"
      dest_url = canonicalise(link["href"])
      p "!!! dest_url #{dest_url.inspect}"
      dest_page = Webpage.find_sole_by(url: dest_url)
      if website.url_internal?(dest_url)
        link["href"] = "#_internal-page-#{dest_page.id}"
        # TODO anchors
      end
    end
    document.css("script").map do |script|
      if script.attribute("src").value.include?("dol-cookie-control.js")
        script.replace("<!- dol-cookie-control.js ->")
      end
    end
    p "!!! document.css(body) #{document.css("body").inspect}"
    p document.css("div#footer-wrapper").to_s
    p body.truncate(200)
    document.css("body")[0]["id"] = "_internal-page-#{id}"
    document.css("body")[0].add_child(timestamp_html)
    File.open("tmp/w.html", "wb") do |file|
      file.write(document.to_html)
      file.close
    end
    pdf = WickedPdf.new.pdf_from_string(document.to_html)
    File.open("tmp/w.pdf", "wb") do |file|
      file.write(pdf)
      file.close
    end
  end

  private

  def canonicalise(uri)
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
    "<div style='font-size:60%;color:#444'>Captured #{Time.now}</div>"
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
