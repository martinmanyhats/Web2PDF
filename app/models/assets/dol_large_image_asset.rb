# frozen_string_literal: true

class DolLargeImageAsset < ContentAsset
  def generate(head: nil, html_filename: nil, pdf_filename: nil)
    super(head: head, html_filename: html_filename, pdf_filename: pdf_filename, preface_html: preface_html)
  end

  def preface_html
    <<-HEREDOC
      Please note that the original web page showed a large and detailed image which could be zoomed and panned.
      Unfortunately it is not possible to replicate this in a PDF.
    HEREDOC
  end
end
