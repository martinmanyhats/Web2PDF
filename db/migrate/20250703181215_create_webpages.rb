class CreateWebpages < ActiveRecord::Migration[8.0]
  def change
    create_table :webpages do |t|
      t.references :website, null: false, foreign_key: true
      t.string :title, default: "-"
      t.string :asset_path, null: false
      t.string :status, null: false
      t.float :scrape_duration
      t.string :content
      t.string :checksum
      t.string :squiz_canonical_url, index: true
      t.integer :squiz_assetid, index: true
      t.string :squiz_short_name
      t.datetime :squiz_updated
      t.string :squiz_breadcrumbs

      t.timestamps
    end
  end
end
