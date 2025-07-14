class CreateWebpages < ActiveRecord::Migration[8.0]
  def change
    create_table :webpages do |t|
      t.references :website, null: false, foreign_key: true
      t.string :title, default: "-"
      t.string :url, null: false
      t.string :canonical_url
      t.string :status, null: false
      t.float :scrape_duration
      t.binary :content
      t.string :checksum
      t.string :squiz_assetid
      t.string :squiz_short_name
      t.datetime :squiz_updated
      t.string :squiz_breadcrumbs

      t.timestamps
    end
  end
end
