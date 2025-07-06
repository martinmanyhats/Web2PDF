class Website < ApplicationRecord
  has_many :webpages, dependent: :destroy

  def scrape
    p "!!! Website::scrape #{inspect}"
    webpage = Webpage.find_or_initialize_by(website: self, url: Webpage.canonicalise(url)) do |page|
      page.status = "unscraped"
      page.website = self
    end
    webpage.scrape
    pp webpage
  end
end
