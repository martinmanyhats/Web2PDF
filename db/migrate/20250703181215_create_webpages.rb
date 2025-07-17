class CreateWebpages < ActiveRecord::Migration[8.0]
  def change
    create_table :webpages do |t|
      t.references :website, null: false, foreign_key: true
      t.references :parent, null: true, foreign_key: { to_table: :webpages }
      t.string :title, default: "-"
      t.string :url, null: false
      t.string :page_path, null: false
      t.string :status, null: false
      t.float :scrape_duration
      t.binary :content
      t.string :checksum
      t.string :squiz_canonical_url
      t.string :squiz_assetid
      t.string :squiz_short_name
      t.datetime :squiz_updated
      t.string :squiz_breadcrumbs

      t.timestamps
    end
  end
end
