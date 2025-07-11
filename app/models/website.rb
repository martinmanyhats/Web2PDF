class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy
  has_one :root_webpage, class_name: "Webpage", dependent: nil

  def scrape(force: false)
    p "!!! Website::scrape #{inspect}"
    webpage = Webpage.find_or_initialize_by(website: self, url: url) do |page|
      page.status = "unscraped"
      page.website = self
    end
    self.root_webpage = webpage
    save!
    webpage.scrape(force: force)
    page_count = 1
    loop do
      unscraped_webpages = Webpage.where(status: "unscraped")
      break if unscraped_webpages.empty?
      unscraped_webpages.each do |page|
        page_count += 1
        return if page_count > 10
        page.scrape(force: force)
      end
    end
  end

  def generate_pdf
    root_webpage.generate_pdf
  end

  def url_internal?(url2)
    p "!!! url #{url} url2 #{url2} #{url2.starts_with?(url)}"
    url2.starts_with?(url)
  end
end
