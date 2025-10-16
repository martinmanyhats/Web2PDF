class AssetUrlsWebpages < ActiveRecord::Migration[8.0]
  def change
    create_table :asset_urls_webpages do |t|
      t.references :webpage, foreign_key: true
      t.references :asset_url, foreign_key: true

      t.timestamps
    end
    add_index :asset_urls_webpages, [:webpage_id, :asset_url_id], unique: true
  end
end
