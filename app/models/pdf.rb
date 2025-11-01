# frozen_string_literal: true

class Pdf
  include Singleton

  ANNOTATION_COLOUR = [100, 100, 100].freeze
  BUTTON_BACKGROUND_COLOUR = [237, 229, 211].freeze
  HOME_LINK_COLOUR = [0, 134, 178].freeze

  def combine_pdfs(website, options)
    p "!!! Pdf:combine_pdfs otions #{options}"
    Rails.logger.silence do
      @combined = HexaPDF::Document.new
      @combined.fonts.add("Symbol")
      contents_outline = @combined.outline.add_item("Contents")
      pdfs_outline = @combined.outline.add_item("PDFs") unless options[:contentonly]
      @combined.catalog[:PageMode] = :UseOutlines

      if options[:assetids].present?
        assetids = options[:assetids].split(",").map(&:to_i)
        content_assets = ContentAsset.where(assetid: assetids)
        pdf_assets = PdfFileAsset.where(assetid: assetids)
        image_assets = ImageAsset.where(assetid: assetids)
        excel_assets = MsExcelDocumentAsset.where(assetid: assetids)
      else
        content_assets = ContentAsset
        pdf_assets = PdfFileAsset
        image_assets = ImageAsset
        excel_assets = MsExcelDocumentAsset
      end
      content_assets = content_assets.publishable.order(:id)
      pdf_assets = pdf_assets.publishable.order(:id)
      image_assets = image_assets.publishable.order(:id)
      excel_assets = excel_assets.publishable.order(:id)
      @page_number = 0

      p "!!! Pdf:combine_pdfs content #{content_assets.count} pdf #{pdf_assets.count}"
      # Combine all pages, adding a PDF destination and contents entry for each.
      @current_asset = Asset.readme
      @page_number = append_asset(@current_asset, @page_number)
      content_assets.each do |asset|
        @current_asset = asset
        next if asset.assetid == Asset::PARISH_ARCHIVE_ASSETID # It is a mess of bad links.
        @page_number += append_asset(asset, @page_number, contents_outline)
      end
      last_content_page_number = @page_number

      unless options[:contentonly]
        assets = pdf_assets.to_a.concat(excel_assets.to_a).concat(image_assets.to_a)
        assets.each do |asset|
          @page_number += append_asset(asset, @page_number, pdfs_outline) { |pdf| add_banner(pdf, asset) }
        end
      end

      # Don't try to fixup non-content PDFS.
      fixup_internal_content_links(0..last_content_page_number-1)
    end

    @combined.catalog[:PageMode] = :UseOutlines
    p "!!! writing @combined"
    @combined.write("#{website.output_root_dir}/combined.pdf", optimize: true)
    @combined
  end

  def append_asset(asset, page_number, outline = nil)
    p "!!! append_asset assetid #{asset.assetid} filename #{asset.generated_filename}"
    pdf = HexaPDF::Document.open(asset.generated_filename)
    if block_given?
      yield pdf
      fixup_pdf(pdf)
    end
    pdf.pages.each do |page|
      page.delete(:Thumb)
      @combined.pages << @combined.import(page)
      if asset.add_footer?
        draw_footer(@combined.pages[-1], asset)
      end
    end
    destination = [@combined.pages[page_number], :FitH, @combined.pages[page_number].box(:media).top]
    @combined.destinations.add(destination_name(asset), destination)
    outline.add_item(asset.clean_short_name, destination: destination) if outline
    p "!!! checking for add_footer class #{asset.class.name}"
    pdf.pages.count
  end

  def fixup_internal_content_links(page_number_range)
    p "!!! fixup_internal_content_links page_number_range #{page_number_range}"
    fixup_errors = []
    p "!!! fixup_internal_content_links pages count #{@combined.pages.count}"
    page_number_range.each do |page_number|
      page = @combined.pages[page_number]
      page.each_annotation do |annotation|
        if annotation.is_a?(HexaPDF::Type::Annotations::Link)
          next if annotation[:A].nil?
          url = annotation[:A][:URI]
          raise "Pdf:fixup_internal_content_links annotation is missing URI" if url.nil?
          matches = url.match(%r{\.\./(\w+)/0*(\d+)-})
          if url.include?("__data") || url.include?("deddingtonhistory.uk")
            fixup_errors << "#{page_number+1}: unresolved url #{url}"
            next
          end
          if matches
            linked_assetid = matches[2].to_i
            linked_asset = Asset.find_by(assetid: linked_assetid)
            raise "Pdf:fixup_internal_content_links cannot find linked_asset linked_assetid #{linked_assetid} url #{url}" if linked_asset.nil?
            p "!!! fixup_internal_content_links #{page_number}: linked_assetid #{linked_asset.assetid} #{linked_asset.short_name}"
            # Replace internal link to linked_asset with PDF link to page destination.
            destinations = @combined.destinations[destination_name(linked_asset)]
            fixup_errors << "#{page_number+1}: missing destinations linked assetid #{linked_asset.assetid} #{linked_asset.short_name}" unless destinations.present?
            next if destinations.nil?
            # p "!!! found destinations for #{destination_name(linked_asset)} #{destinations.map{ it.class.name }}" if destinations
            raise "Pdf:fixup_internal_content_links missing page destination #{linked_assetid} #{destination_name(linked_asset)}" unless destinations[0].is_a?(HexaPDF::Type::Page)
            annotation[:A] = { S: :GoTo, D: destinations }
          end
          # TODO intra-page links to anchors
        end
      end
    end
    fixup_errors.each { puts(">>> #{it}") }
  end

  def add_banner(pdf, asset = nil)
    p "!!! add_banner assetid #{asset&.assetid}"
    page = pdf.pages[0]
    canvas = page.canvas(type: :overlay)
    if asset
      canvas.fill_color(*ANNOTATION_COLOUR)
      canvas.font("Helvetica", size: 9)
      canvas.text(asset.banner_title, at: [2, page.box.height - 10])
    end
    add_home_button(pdf)
    #add_back_button(pdf)
  end

  def add_home_button(pdf)
    page = pdf.pages[0]
    box_width = 32
    box_height = 10
    offset_x = offset_y = 2
    box_x = page.box.width - box_width - offset_x
    box_y = page.box.height - box_height - offset_y
    link_rect = [box_x, box_y, box_x + box_width, box_y + box_height]
    canvas = page.canvas(type: :overlay)
    canvas.fill_color(button_background_color)
    canvas.rectangle(*link_rect).fill
    canvas.fill_color(*HOME_LINK_COLOUR)
    canvas.font("Helvetica", size: 10)
    canvas.text("Home", at: [box_x + 2, box_y + offset_y])
    link = pdf.add({
                     Type: :Annot,
                     Subtype: :Link,
                     Rect: link_rect,
                     Dest: destination_name(Asset.home)
                   })
    page[:Annots] ||= []
    page[:Annots] << link
  end

  def add_back_button(pdf)
    w = 100
    h = 12
    page = pdf.pages[0]
    page_height = page.box.height
    page_width = page.box.width
    button_rect = [page_width - 50, page_height - 20, page_width, page_height - 40]
    p "!!! button_rect #{button_rect}"
    form = pdf.acro_form(create: true)
    button = pdf.add({
                       Type: :Annot,
                       Subtype: :Widget,
                       FT: :Btn,              # Button field type
                       Ff: 65536,             # Push button flag (bit 17)
                       T: "Back#{@current_asset.assetid_formatted}", # Unique field name
                       Rect: button_rect,
                       P: page,
                       RC: "Go back to previous page",
                       MK: {
                         BG: [0.9, 0, 0], #button_background_color,
                         BC: [0, 0, 0], # Black border
                         CA: 'Back', # Caption text
                       }
                     })

    # Set border style
    false && button[:BS] = {
      W: 1,  # Border width
      S: :S  # Solid border
    }

    # Add action to go to previous page
    button[:A] = pdf.add({
                           Type: :Action,
                           S: :Named,
                           N: :GoBack
                         })
    page[:Annots] ||= []
    page[:Annots] << button
    form[:Fields] ||= []
    form[:Fields] << button
  end

  def draw_footer(page, asset = nil)
    p "!!! draw_footer"
    canvas = page.canvas(type: :overlay)
    canvas.fill_color(*ANNOTATION_COLOUR)
    footer_text = "1998–#{Date.today.year} Deddington OnLine"
    canvas.font("Symbol", size: 10)
    canvas.text(0xe3.chr(Encoding::UTF_8), at: [20, 4])
    canvas.font("Helvetica", size: 10)
    canvas.text(footer_text, at: [32, 4])
    canvas.text("##{asset.assetid}", at: [page.box.width - 40, 4])
  end

  def fixup_pdf(pdf)
    catalog = pdf.catalog
    if catalog
      # p "!!! fixup_pdf catalog[:ViewerPreferences] #{catalog[:ViewerPreferences].inspect}"
      # p "!!! fixup_pdf catalog[:PageMode] #{catalog[:PageMode].inspect}"
      if catalog[:ViewerPreferences]
        if catalog[:ViewerPreferences][:NonFullScreenPageMode] == :None
          # p "!!! fixup_pdf NonFullScreenPageMode"
          catalog[:ViewerPreferences][:NonFullScreenPageMode] = :UseNone
        end
      end
      if catalog[:PageMode] == :None
        # p "!!! fixup_pdf PageMode"
        catalog[:PageMode] = :UseNone
      end
    end
  end

  def destination_name(asset)
    "w2p-destination-#{asset.assetid_formatted}"
  end

  def convert_to_rgb(rgb) = rgb.map { it / 256.0 }

  def button_background_color
    @_button_background_color ||= convert_to_rgb(BUTTON_BACKGROUND_COLOUR)
  end
end
