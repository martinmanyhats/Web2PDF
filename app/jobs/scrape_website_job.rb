class ScrapeWebsiteJob < ApplicationJob
  queue_as :default

  def perform(website)
    p "!!! ScrapeWebsiteJob::perform website #{website.inspect}"
    website.scrape(force: true)#, page_limit: 20)
  end
end
