class WebsitesController < ApplicationController
  before_action :set_website, only: %i[ show edit update destroy scrape generate_pdf ]

  # GET /websites or /websites.json
  def index
    @websites = Website.all
  end

  # GET /websites/1 or /websites/1.json
  def show
  end

  # GET /websites/new
  def new
    @website = Website.new
  end

  # GET /websites/1/edit
  def edit
  end

  # POST /websites or /websites.json
  def create
    @website = Website.new(website_params)

    respond_to do |format|
      if @website.save
        format.html { redirect_to @website, notice: "Website was successfully created." }
        format.json { render :show, status: :created, location: @website }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @website.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /websites/1 or /websites/1.json
  def update
    respond_to do |format|
      if @website.update(website_params)
        format.html { redirect_to @website, notice: "Website was successfully updated." }
        format.json { render :show, status: :ok, location: @website }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @website.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /websites/1 or /websites/1.json
  def destroy
    @website.destroy!

    respond_to do |format|
      format.html { redirect_to websites_path, status: :see_other, notice: "Website was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def scrape
    follow_links = true
    if params[:unscrape].present?
      assetid = params[:unscrape].to_i
      webpage = Webpage.find_by(squiz_assetid: assetid)
      if webpage
        webpage.status = "unscraped"
        webpage.save!
      end
      follow_links = false
    end
    ScrapeWebsiteJob.perform_later(@website, follow_links: follow_links)
  end

  def generate_pdf
    if params[:assetid].present?
      assetid = params[:assetid].to_i
      @website.generate_pdf_files(assetids: [assetid])
    else
      @website.generate_pdf_files
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_website
      @website = Website.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def website_params
      params.expect(website: [ :name, :url, :auto_refresh, :refresh_period, :publish_url, :status, :notes ])
    end
end
