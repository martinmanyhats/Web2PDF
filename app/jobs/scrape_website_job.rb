class ScrapeWebsiteJob < ApplicationJob
  queue_as :default

  def perform(website, follow_links: true)
    p "!!! ScrapeWebsiteJob::perform website #{website.inspect}"
    website.scrape(follow_links: follow_links)
  end
end
