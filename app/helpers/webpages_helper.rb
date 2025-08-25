module WebpagesHelper
  def linked_page_path(webpage)
    webpage.page_path.split(".").map {|id| "#{link_to id, Webpage.find(id)}"}.join(".").html_safe
  end
end
