json.extract! website, :id, :name, :url, :auto_refresh, :refresh_period, :publish_url, :status, :notes, :created_at, :updated_at
json.url website_url(website, format: :json)
