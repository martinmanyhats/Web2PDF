class ScrapeWebsiteJob < ApplicationJob
  queue_as :default

  def perform(website, options)
    p "!!! ScrapeWebsiteJob::perform website options #{options.inspect} #{website.inspect}"
    website.scrape(options)
  end
end
