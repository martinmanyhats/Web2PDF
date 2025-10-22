# frozen_string_literal: true

class Link < ActiveRecord::Base
  belongs_to :source, class_name: "Asset"
  belongs_to :destination, class_name: "Asset"
end
