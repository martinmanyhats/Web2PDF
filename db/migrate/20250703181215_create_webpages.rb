class CreateWebpages < ActiveRecord::Migration[8.0]
  def change
    create_table :webpages do |t|
      t.references :website, null: false, foreign_key: true
      t.string :title, default: "-"
      t.string :url, null: false
      t.string :status, null: false
      t.float :scrape_duration
      t.binary :body
      t.string :checksum

      t.timestamps
    end
  end
end
