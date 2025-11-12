# frozen_string_literal: true

class Pdf
  include Singleton

  ANNOTATION_COLOUR = [100, 100, 100].freeze
  BUTTON_BACKGROUND_COLOUR = [237, 229, 211].freeze
  HOME_LINK_COLOUR = [0, 134, 178].freeze

  def combine_pdfs(website, options)
    p "!!! Pdf:combine_pdfs otions #{options}"
    @pdf_errors = []
    Rails.logger.silence do
      @combined_pdf = HexaPDF::Document.new
      @combined_pdf.fonts.add("Symbol")
      @combined_pdf.catalog[:PageMode] = :UseOutlines

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

      content_assets = content_assets.sitemap_ordered
      pdf_assets = pdf_assets.publishable.order(:id)
      image_assets = image_assets.publishable.order(:id)
      excel_assets = excel_assets.publishable.order(:id)
      contents_outline = @combined_pdf.outline.add_item("Contents")

      not_in_sitemap = ContentAsset.where(status: "spidered") - content_assets
      if not_in_sitemap.present?
        puts("!!! not_in_sitemap.size #{not_in_sitemap.size}")
        not_in_sitemap.each do |asset|
          @pdf_errors << "not in sitemap: #{asset.assetid} #{asset.short_name}"
        end
      end

      @page_number = 0
      @fixup_pages = []
      # Combine all pages, adding a PDF destination and contents entry for each.
      content_assets.each do |asset|
        raise "Pdf:combine_pdfs not ContentAsset #{asset.assetid}" unless asset.is_a?(ContentAsset)
        page_count = append_asset(asset, contents_outline)
        # Skip due to mess of bad links.
        skip = [ContentAsset::parish_archive].include?(asset)
        @fixup_pages.append(*Array.new(page_count, !skip))
        @page_number += page_count
      end
      p "!!! last content @page_number #{@page_number}"
      p "!!! @fixup_pages.true #{@fixup_pages.select{it}.size}"

      if options[:includepdfs]
        @page_number += append_assets("PDFs", pdf_assets)
      end
      @page_number += append_assets("Images", image_assets)
      @page_number += append_assets("Excel files", excel_assets)
      p "!!! combine_pdfs last @page_number #{@page_number}"

      if options[:dumpdestinations].present?
        @combined_pdf.destinations.each { |name, dest| p "!!! #{name} #{dest}" }
      end

      fixup_internal_content_links(options[:includepdfs])
      set_initial_view
    end

    @combined_pdf.catalog[:PageMode] = :UseOutlines
    p "!!! writing @combined_pdf"
    filename = "DeddingtonHistory-#{DateTime.now.strftime("%Y%m%d")}.pdf"
    @combined_pdf.write("#{website.output_root_dir}/#{filename}", optimize: true)
    @pdf_errors.each { puts(">>> #{it}") }
    @combined_pdf
  end

  def append_assets(name, assets)
    outline = @combined_pdf.outline.add_item(name)
    page_count = 0
    assets.all.each do |asset|
      page_count += append_asset(asset, outline) { |pdf| add_banner(pdf, asset) }
      @fixup_pages[@page_number..@page_number+page_count-1] = false
    end
    page_count
  end

  def append_asset(asset, outline = nil)
    p "!!! append_asset assetid #{asset.assetid} filename #{asset.generated_filename}"
    pdf = HexaPDF::Document.open(asset.generated_filename)
    if block_given?
      yield pdf
      fixup_pdf(pdf)
    end
    pdf.pages.each do |page|
      page.delete(:Thumb)
      @combined_pdf.pages << @combined_pdf.import(page)
      if asset.add_footer?
        draw_footer(@combined_pdf.pages[-1], asset)
      end
    end
    destination = [@combined_pdf.pages[@page_number], :FitH, @combined_pdf.pages[@page_number].box(:media).top]
    @combined_pdf.destinations.add(destination_name(asset), destination)
    outline.add_item(asset.clean_short_name, destination: destination) if outline
    # p "!!! checking for add_footer class #{asset.class.name}"
    pdf.pages.count
  end

  def set_initial_view
    # Sadly most browsers will ignore.
    @combined_pdf.catalog[:ViewerPreferences] ||= {}
    @combined_pdf.catalog[:ViewerPreferences][:FitWindow] = true
    prefs = @combined_pdf.catalog[:ViewerPreferences]
    p "!!! Pdf:set_initial_view catalog #{prefs.each.map{ "#{it}=#{prefs[it]} "} }"
  end

  def fixup_internal_content_links(include_pdfs)
    p "!!! fixup_internal_content_links size #{@fixup_pages.size}"
    p "!!! fixup_internal_content_links pages count #{@combined_pdf.pages.count}"
    @fixup_pages.each_index do |page_number|
      print "\r!!! page_number #{page_number}" if (page_number % 20) == 0
      next unless @fixup_pages[page_number]
      page = @combined_pdf.pages[page_number]
      page.each_annotation.select { it[:Subtype] == :Link }.each do |annotation|
        if annotation.is_a?(HexaPDF::Type::Annotations::Link)
          next if annotation[:A].nil?
          url = annotation[:A][:URI]
          raise "Pdf:fixup_internal_content_links annotation is missing URI #{annotation.inspect}" if url.nil?
          url = annotation[:A][:URI]
          p "!!! page_number #{page_number} url #{url}"
          if url.start_with?("intasset://")
            matches = url.match(%r{intasset://(\d+):(\d+)})
            raise "Pdf:fixup_internal_content_links malformed url #{url}" if matches.nil? || matches.length != 3
            linked_assetid = matches[1].to_i
            source_assetid = matches[2].to_i
            linked_asset = Asset.find_by(assetid: linked_assetid)
            raise "Pdf:fixup_internal_content_links cannot find linked_asset #{linked_assetid} #{url} source #{source_assetid}" if linked_asset.nil?
            next if linked_asset.is_a?(PdfFileAsset) && !include_pdfs
            # Replace internal link to linked_asset with a PDF link to page destination.
            p "!!! destination_name(linked_asset) #{destination_name(linked_asset)}"
            destinations = @combined_pdf.destinations[destination_name(linked_asset)]
            p "!!! found destinations for #{destination_name(linked_asset)} #{destinations.map{ it.class.name }}" if destinations
            unless destinations.present? && destinations[0].is_a?(HexaPDF::Type::Page)
              raise "Pdf:fixup_internal_content_links missing page destination #{linked_assetid} #{destination_name(linked_asset)} source #{source_assetid}"
            end
            annotation[:A] = {S: :GoTo, D: destinations}
          elsif url.start_with?("extasset://")
            p "!!! TODO #{url}"
          end
        end
        next
=begin
        if annotation.is_a?(HexaPDF::Type::Annotations::Link)
          next if annotation[:A].nil?
          url = annotation[:A][:URI]
          raise "Pdf:fixup_internal_content_links annotation is missing URI #{annotation.inspect}" if url.nil?
          p "!!! page_number #{page_number} url #{url}"
          if url.include?("__data") || url.include?("//deddingtonhistory.uk")
            p "!!! fixup #{page_number+1}: unresolved url #{url}"
            @pdf_errors << "#{page_number+1}: unresolved url #{url}"
            next
          end
          matches = url.match(%r{\.\./(\w+)/*(\d{5})-})
          if matches
            linked_assetid = matches[2].to_i
            linked_asset = Asset.find_by(assetid: linked_assetid)
            raise "Pdf:fixup_internal_content_links cannot find linked_asset linked_assetid #{linked_assetid} url #{url}" if linked_asset.nil?
            # Replace internal link to linked_asset with a PDF link to page destination.
            destinations = @combined_pdf.destinations[destination_name(linked_asset)]
            if destinations.nil? || destinations.empty?
              if include_pdfs
                @pdf_errors << "#{page_number+1}: missing destinations linked asset #{linked_asset.assetid} #{linked_asset.short_name}"
              else
                # Asset must be external.
                fixup_external_link(annotation, linked_asset)
              end
              next
            end
            p "!!! found destinations for #{destination_name(linked_asset)} #{destinations.map{ it.class.name }}" if destinations
            raise "Pdf:fixup_internal_content_links missing page destination #{linked_assetid} #{destination_name(linked_asset)}" unless destinations[0].is_a?(HexaPDF::Type::Page)
            annotation[:A] = {S: :GoTo, D: destinations}
          end
        end
=end
      end
    end
    p "!!! finished fixup"
  end

  def fixup_external_link(annotation, linked_asset)
    # Add tooltip and link to external file explainer page.
    tooltip_text = "Asset ##{linked_asset.assetid_formatted}"
    annotation[:Contents] = tooltip_text
  end

  def add_banner(pdf, asset = nil)
    # p "!!! add_banner assetid #{asset&.assetid}"
    page = pdf.pages[0]
    canvas = page.canvas(type: :overlay)
    if asset
      canvas.fill_color(*ANNOTATION_COLOUR)
      canvas.font("Helvetica", size: 9)
      canvas.text(asset.banner_title, at: [2, page.box.height - 10])
      #add_back_button(pdf, asset)
    end
    add_home_button(pdf)
  end

  def add_home_button(pdf)
    page = pdf.pages[0]
    box_width = 32
    box_height = 13
    box_x = page.box.width - box_width
    box_y = page.box.height - box_height
    link_rect = [box_x, box_y, box_x + box_width, box_y + box_height]
    canvas = page.canvas(type: :overlay)
    canvas.fill_color(button_background_color)
    canvas.rectangle(*link_rect).fill
    canvas.fill_color(*HOME_LINK_COLOUR)
    canvas.font("Helvetica", size: 10)
    canvas.text("Home", at: [box_x + 3, box_y + 3])
    link = pdf.add({
                     Type: :Annot,
                     Subtype: :Link,
                     Rect: link_rect,
                     Dest: destination_name(ContentAsset.home)
                   })
    page[:Annots] ||= []
    page[:Annots] << link
  end

  def add_back_button(pdf, asset)
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
                       T: "Back#{asset.assetid_formatted}", # Unique field name
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
    # p "!!! draw_footer"
    canvas = page.canvas(type: :overlay)
    canvas.fill_color(*ANNOTATION_COLOUR)
    footer_text = "1998–#{Date.today.year} Deddington OnLine"
    canvas.font("Symbol", size: 10)
    canvas.text(0xe3.chr(Encoding::UTF_8), at: [20, 4])
    canvas.font("Helvetica", size: 10)
    canvas.text(footer_text, at: [32, 4])
    canvas.text("##{asset.assetid_formatted}", at: [page.box.width - 40, 4])
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
