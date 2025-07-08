class Webpage < ApplicationRecord
  belongs_to :website
  has_many :weblinks, foreign_key: "from_id",dependent: :delete_all

  def self.canonicalise(url)
    p "!!! url #{url}"
    url.delete_suffix("/")
  end

  def scrape
    p "!!! Webpage::scrape url #{url}"
    document = Nokogiri::HTML(get_body(url))
    @checksum = Digest::SHA256.hexdigest(response.body)
    @scrape_duration = Time.now - start
    links = document.css("a").map{ |a| a.attribute("href") }
    links = links.limit(2)
    p "!!! Webpage::scrape links #{links.map{|l| l.value}.join(" | ")}"
    links.each do |link|
      linkurl = Webpage.canonicalise(link.value)
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
        p "!!! new link: #{link.inspect}"
      end
    end
    @status = "scraped"
    p "!!! Webpage::scrape #{inspect}"
    save!
  end

  def to_pdf
    p "!!! Webpage::to_pdf"
    # url = "https://martinreed.co.uk/"
    url = "https://www.deddingtonhistory.uk/worldwars/thecivilwar1642-49"
    body = get_body(url)
    filtered_body = body.lines.map do |line|
      case line
      when /.*script.*cookieControl.*/
        ""
      when /<img.*src="\//
        line = line.gsub(/src="/, "src=\"https://deddingtonhistory.uk")
        p "!!! img #{line}"
        line
      else
        line
      end
    end
    pdf = WickedPdf.new.pdf_from_string(filtered_body.join("\n"))
    File.open("tmp/w.pdf", "wb") do |file|
      file.write(pdf)
      file.close
    end
  end

  def get_body(url)
    p "!!! Webpage::get_body url #{url}"
    response = HTTParty.get(url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    response.body
  end
end
