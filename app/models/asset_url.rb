class AssetUrl < ApplicationRecord
  belongs_to :asset
  belongs_to :webpage, optional: true
end
