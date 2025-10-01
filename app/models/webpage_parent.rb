class WebpageParent < ApplicationRecord
  belongs_to :webpage
  belongs_to :parent, class_name: 'Webpage'
end
