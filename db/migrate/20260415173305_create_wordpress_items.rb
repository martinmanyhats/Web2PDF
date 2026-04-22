class CreateWordpressItems < ActiveRecord::Migration[8.1]
  def change
    create_table :wordpress_items do |t|
      t.integer :itemid, null: false, index: true
      t.string :slug, null: false
      t.string :url, null: false
      t.string :squiz_url, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
