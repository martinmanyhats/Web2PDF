json.extract! weblink, :id, :webpage_from_id, :webpage_to_id, :linktype, :linkvalue, :info, :created_at, :updated_at
json.url weblink_url(weblink, format: :json)
