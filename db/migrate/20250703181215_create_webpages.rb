class CreateWebpages < ActiveRecord::Migration[8.0]
  def change
    create_table :webpages do |t|
      t.references :website, null: false, foreign_key: true
      t.string :name
      t.string :url, null: false
      t.string :status, null: false
      t.integer :scrape_duration
      t.string :checksum

      t.timestamps
    end
  end
end
