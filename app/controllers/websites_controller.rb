class WebsitesController < ApplicationController
  before_action :set_website, only: %i[ show edit update destroy spider generate_archive zip_archive combine_pdfs experiment ]

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

  def spider
    options = {}
    options[:assetid] = params[:assetid].to_i if params[:assetid].present?
    SpiderWebsiteJob.perform_later(@website, options)
  end

  def extract
    options = {}
    options[:assetid] = params[:assetid].to_i if params[:assetid].present?
    options[:skiplist] = params[:assetid].to_i if params[:skiplist].present?
    ExtractWebsiteJob.perform_later(@website, options)
  end

  def generate_archive
    options = {}
    options[:webroot] = params[:webroot] if params[:webroot].present?
    options[:assetids] = params[:assetids].to_s if params[:assetids].present?
    options[:contentonly] = params[:contentonly].to_s if params[:contentonly].present?
    options[:digest] = true if params[:digest].present?
    @website.generate_archive(options)
  end

  def zip_archive
    @zip_filename = @website.zip_archive
  end

  def combine_pdfs
    options = {}
    options[:assetids] = params[:assetids].to_s if params[:assetids].present?
    options[:dumpdestinations] = params[:dumpdestinations] if params[:dumpdestinations].present?
    @combined_pdf = Pdf.instance.combine_pdfs(Website.find(1), options)
  end
  def experiment
    @website.asset_sort_order
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
