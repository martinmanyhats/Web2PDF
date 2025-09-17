class SpiderWebsiteJob < ApplicationJob
  queue_as :default

  def perform(website, options)
    p "!!! SpiderWebsiteJob::perform website options #{options.inspect} #{website.inspect}"
    website.spider(options)
  end
end
