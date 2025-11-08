# frozen_string_literal: true

require 'open-uri'

class ImageAsset < DataAsset
  def self.output_dir = "image"
  def self.toc_name = "Images"

  def self.XXgenerate(website, assetids)
    assets = super
    # TODO TOC
  end

  def generate
    header_height = 18
    image_pdf = HexaPDF::Document.new
    image_path = url
    p "!!! ImageAsset:generate filename #{image_path}"
    if File.extname(image_path).downcase == ".gif"
      img = Vips::Image.new_from_buffer(URI.open(image_path, &:read), "")
      image_path = "#{Dir.tmpdir}/#{filename_base.sub(%r{gif$}i, "png")}"
      img.write_to_file(image_path)
    end
    image = image_pdf.images.add(URI.open(image_path))
    canvas_width = [image.info.width, 300].max # Allow enough for header.
    page = image_pdf.pages.add
    page.box(:media).width  = canvas_width
    page.box(:media).height = image.info.height + header_height
    canvas = page.canvas
    # Add header stripe above image.
    canvas.fill_color(237, 229, 211)
    canvas.rectangle(0, image.info.height, canvas_width, image.info.height).fill
    canvas.image(image, at: [(canvas_width - image.info.width)/2, 0], width: image.info.width, height: image.info.height)
    image_pdf.write(filename_with_assetid("pdf", "pdf"), optimize: true)
  end

  def generated_filename
    "#{website.output_root_dir}/pdf/#{filename_base}.pdf"
  end

  def banner_title = name
end
