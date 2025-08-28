module WebpagesHelper
  def linked_page_path(webpage)
    webpage.asset_path
    # webpage.asset_path.split("/").map {|assetid| "#{link_to assetid, Webpage.find_by_squiz_assetid(assetid)}"}.join("/").html_safe
  end
end
