class Webpage < ApplicationRecord
  belongs_to :website
  has_many :weblinks, foreign_key: "from_id",dependent: :delete_all

  def self.canonicalise(url)
    p "!!! url #{url}"
    url.delete_suffix("/")
  end

  def scrape
    p "!!! Webpage::scrape url #{url}"
    start = Time.now
    response = HTTParty.get(url, {
      headers: {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
      },
    })
    document = Nokogiri::HTML(response.body)
    checksum = Digest::SHA256.hexdigest(response.body)
    scrape_duration = Time.now - start
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
    self.status = "scraped"
    p "!!! Webpage::scrape #{inspect}"
    save!
  end
end
