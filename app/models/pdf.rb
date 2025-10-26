# frozen_string_literal: true

class Pdf
  def self.combine_pdfs(website)
    self.new.combine_pdfs(website)
  end

  def combine_pdfs(website)
    @combined = HexaPDF::Document.new
    contents = @combined.outline.add_item("Contents")
    page_number = 0
    # Combine all pages, adding a PDF destination and contents entry for each.
    ContentAsset.publishable.order(:id).each do |asset|
      p "!!! assetid #{asset.assetid} short_name #{asset.short_name} filename #{asset.generated_filename}"
      pdf = HexaPDF::Document.open(asset.generated_filename)
      pdf.pages.each { |page| @combined.pages << @combined.import(page) }
      destination = [@combined.pages[page_number], :FitH, @combined.pages[page_number].box(:media).top]
      @combined.destinations.add(destination_name(asset), destination)
      contents.add_item(asset.short_name, destination: destination)
      page_number += pdf.pages.count
    end

    fixup_internal_content_links

    p "!!! writing @combined"
    @combined.write("#{website.output_root_dir}/combined.pdf", optimize: true)
  end

  def fixup_internal_content_links
    fixup_errors = []
    p "!!! pages size #{@combined.pages.size}"
    @combined.pages.each_with_index  do |page, page_number|
      page.each_annotation do |annotation|
        if annotation.is_a?(HexaPDF::Type::Annotations::Link)
          next if annotation[:A].nil?
          url = annotation[:A][:URI]
          raise "Pdf:fixup_internal_content_links annotation is missing URI" if url.nil?
          # p "!!! annotation: #{annotation.inspect}"
          matches = url.match(%r{\.\./(\w+)/0*(\d+)-})
          # raise "Pdf:fixup_internal_content_links unresolved DH url #{url}" if url.include?("www.deddingtonhistory.uk")
          if url.include?("__data") || url.include?("www.deddingtonhistory.uk")
            fixup_errors << "page #{page_number} unresolved url #{url}"
            next
          end
          p "!!! matches #{matches.inspect} url #{url}"
          if matches
            assetid = matches[2].to_i
            # p "!!! annotation url #{url} assetid #{assetid}"
            asset = Asset.find_by(assetid: assetid)
            raise "Pdf:fixup_internal_content_links cannot find asset assetid #{assetid} url #{url}" if asset.nil?
            p "!!! asset assetid #{asset.assetid} #{asset.short_name}"
            if asset.is_a?(ContentAsset)
              # Replace internal link to asset with PDF link to page destination.
              destinations = @combined.destinations[destination_name(asset)]
              next if destinations.nil?
              # raise "Pdf:fixup_internal_content_links destination not found for assetid #{assetid}" if destinations.nil?
              p "!!! found destinations for #{destination_name(asset)} #{destinations.map{ it.class.name }}" if destinations
              raise "Pdf:fixup_internal_content_links missing page destination #{assetid} #{destination_name(asset)}" unless destinations[0].is_a?(HexaPDF::Type::Page)
              annotation[:A] = { S: :GoTo, D: destinations }
            end
          end
          # TODO intra-page links to anchors
        end
      end
    end
    fixup_errors.each { puts(">>> #{it}") }
  end

  def destination_name(asset)
    "w2p-page-#{asset.assetid_formatted}"
  end
end
