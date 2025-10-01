module WebpagesHelper
  def linked_page_path(webpage)
    webpage.asset_path
  end
end
