class ScrapeWebsiteJob < ApplicationJob
  queue_as :default

  def perform(website, options)
    p "!!! ScrapeWebsiteJob::perform website options #{options.inspect} #{website.inspect}"
    website.spider(options)
  end
end
