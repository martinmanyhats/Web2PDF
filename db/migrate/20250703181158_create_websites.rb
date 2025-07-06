class CreateWebsites < ActiveRecord::Migration[8.0]
  def change
    create_table :websites do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :auto_refresh, default: false
      t.integer :refresh_period, default: 60 * 60 * 24
      t.string :publish_url
      t.string :status, null: false, default: "unscraped"
      t.string :notes

      t.timestamps
    end
  end
end
