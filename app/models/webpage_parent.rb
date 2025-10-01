class WebpageParent < ApplicationRecord
  belongs_to :webpage
  belongs_to :parent, class_name: "Webpage"

  def parent_paths
    #if parent.assetid != Webpage::HOME_SQUIZ_ASSETID
    #[parent.]
  end
end
