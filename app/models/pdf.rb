# frozen_string_literal: true

class Pdf
  def self.combine_pdfs(website, options = {})
    self.new.combine_pdfs(website, options)
  end

  def combine_pdfs(website, options)
    Rails.logger.silence do
      @combined = HexaPDF::Document.new
      contents_outline = @combined.outline.add_item("Contents")
      pdfs_outline = @combined.outline.add_item("PDFs") if options[:includeall]
      @combined.catalog[:PageMode] = :UseOutlines

      if options[:assetids].present?
        assetids = options[:assetids].split(",").map(&:to_i)
        assets = ContentAsset.where(assetid: assetids)
      else
        assets = ContentAsset.publishable.order(:id)
      end
      page_number = 0

      # Combine all pages, adding a PDF destination and contents entry for each.
      assets.each do |asset|
        next if asset.assetid == Asset::PARISH_ARCHIVE_ASSETID # It is a mess of bad links.
        page_number += append_asset(asset, page_number, contents_outline)
      end
      last_content_page_number = page_number
      if options[:includeall]
        PdfFileAsset.publishable.order(:id).each do |asset|
          page_number += append_asset(asset, page_number, pdfs_outline)
        end
      end

      # Don't try to fixup non-content PDFS.
      fixup_internal_content_links(0..last_content_page_number-1)
    end

    p "!!! writing @combined"
    @combined.write("#{website.output_root_dir}/combined.pdf", optimize: true)
    @combined
  end

  def append_asset(asset, page_number, outline)
    p "!!! append_asset assetid #{asset.assetid} filename #{asset.generated_filename}"
    pdf = HexaPDF::Document.open(asset.generated_filename)
    pdf.pages.each do |page|
      page.delete(:Thumb)
      @combined.pages << @combined.import(page)
    end
    destination = [@combined.pages[page_number], :FitH, @combined.pages[page_number].box(:media).top]
    @combined.destinations.add(destination_name(asset), destination)
    outline.add_item(asset.clean_short_name, destination: destination)
    pdf.pages.count
  end

  def fixup_internal_content_links(page_number_range)
    p "!!! fixup_internal_content_links page_number_range #{page_number_range}"
    fixup_errors = []
    p "!!! pages count #{@combined.pages.count}"
    page_number_range.each do |page_number|
      page = @combined.pages[page_number]
      page.each_annotation do |annotation|
        if annotation.is_a?(HexaPDF::Type::Annotations::Link)
          p "!!! page_number #{page_number} annotation #{annotation.inspect}"
          next if annotation[:A].nil?
          url = annotation[:A][:URI]
          raise "Pdf:fixup_internal_content_links annotation is missing URI" if url.nil?
          matches = url.match(%r{\.\./(\w+)/0*(\d+)-})
          # raise "Pdf:fixup_internal_content_links unresolved DH url #{url}" if url.include?("www.deddingtonhistory.uk")
          if url.include?("__data") || url.include?("www.deddingtonhistory.uk")
            fixup_errors << "page #{page_number} unresolved url #{url}"
            next
          end
          p "!!! matches #{matches.inspect} url #{url}"
          if matches
            linked_assetid = matches[2].to_i
            # p "!!! annotation url #{url} linked_assetid #{linked_assetid}"
            linked_asset = Asset.find_by(assetid: linked_assetid)
            raise "Pdf:fixup_internal_content_links cannot find linked_asset linked_assetid #{linked_assetid} url #{url}" if linked_asset.nil?
            p "!!! linked_asset linked_assetid #{linked_asset.assetid} #{linked_asset.short_name} page_number #{page_number}"
            #if linked_asset.is_a?(ContentAsset)
              # Replace internal link to linked_asset with PDF link to page destination.
              destinations = @combined.destinations[destination_name(linked_asset)]
              next if destinations.nil?
              # raise "Pdf:fixup_internal_content_links destination not found for linked_assetid #{linked_assetid}" if destinations.nil?
              p "!!! found destinations for #{destination_name(linked_asset)} #{destinations.map{ it.class.name }}" if destinations
              raise "Pdf:fixup_internal_content_links missing page destination #{linked_assetid} #{destination_name(linked_asset)}" unless destinations[0].is_a?(HexaPDF::Type::Page)
              annotation[:A] = { S: :GoTo, D: destinations }
              #elsif linked_asset.is_a?(DataAsset)
              #annotation[:A][:URI] = url.delete_prefix("../")
              #p "!!! DataAsset url #{url} annotation #{annotation.inspect}"
            #end
          end
          # TODO intra-page links to anchors
        end
      end
    end
    fixup_errors.each { puts(">>> #{it}") }
  end

  def append_pdfs
    PdfFileAsset.publishable.order(:id).each do |asset|

    end
  end

  def destination_name(asset)
    "w2p-destination-#{asset.assetid_formatted}"
  end
end
