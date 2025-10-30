# frozen_string_literal: true
require 'open-uri'

class ImageAsset < DataAsset
  def self.output_dir = "image"
  def self.toc_name = "Images"

  def self.generate(website, image_assets)
    images_pdf = HexaPDF::Document.new
    image_assets.each do |asset|
      image_path = asset.url
      p "!!! ImageAsset:generate filename #{image_path}"
      if File.extname(asset.url).downcase == ".gif"
        img = Vips::Image.new_from_buffer(URI.open(asset.url, &:read), "")
        image_path = "#{Dir.tmpdir}/#{asset.filename_base.sub(%r{gif$}i, "png")}"
        img.write_to_file(image_path)
      end
      image = images_pdf.images.add(URI.open(image_path))
      page = images_pdf.pages.add
      page.box(:media).width  = image.info.width
      page.box(:media).height = image.info.height
      canvas = page.canvas
      canvas.image(image, at: [0, 0], width: image.info.width, height: image.info.height)
    end
    images_pdf.write("#{website.output_root_dir}/pdf/images.pdf", optimize: true)
  end
end
