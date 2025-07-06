json.extract! webpage, :id, :website_id, :h1, :url, :checksum, :created_at, :updated_at
json.url webpage_url(webpage, format: :json)
