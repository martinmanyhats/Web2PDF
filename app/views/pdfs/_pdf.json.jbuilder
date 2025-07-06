json.extract! pdf, :id, :website_id, :url, :size, :notes, :created_at, :updated_at
json.url pdf_url(pdf, format: :json)
