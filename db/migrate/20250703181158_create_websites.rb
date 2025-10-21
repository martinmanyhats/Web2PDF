class CreateWebsites < ActiveRecord::Migration[8.0]
  def change
    create_table :websites do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :auto_refresh, default: false
      t.integer :refresh_period, default: 60 * 60 * 24
      t.string :output_root_dir, null: false
      t.string :publish_url, null: false
      t.datetime :last_scraped
      t.string :remove_scripts, default: ""
      t.string :css, default: ""
      t.string :javascript, default: ""
      t.string :notes, default: ""

      t.timestamps
    end
  end
end
