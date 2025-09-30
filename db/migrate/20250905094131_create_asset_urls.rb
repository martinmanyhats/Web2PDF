class CreateAssetUrls < ActiveRecord::Migration[8.0]
  def change
    create_table :asset_urls do |t|
      t.string :url
      t.references :asset, null: false, foreign_key: true
      t.references :webpage, null: true, foreign_key: true

      t.timestamps
    end
    add_index :asset_urls, :url, unique: true
  end
end
