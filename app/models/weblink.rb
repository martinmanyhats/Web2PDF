class Weblink < ApplicationRecord
  belongs_to :from, class_name: "Webpage"
  belongs_to :to, class_name: "Webpage"
end
