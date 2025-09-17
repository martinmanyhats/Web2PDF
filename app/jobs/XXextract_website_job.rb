class ExtractWebsiteJob < ApplicationJob
  queue_as :default

  def perform(website, options)
    p "!!! ExtractWebsiteJob::perform website options #{options.inspect} #{website.inspect}"
    website.extract(options)
  end
end
