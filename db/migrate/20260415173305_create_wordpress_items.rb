class CreateWordpressItems < ActiveRecord::Migration[8.1]
  def change
    create_table :wordpress_items do |t|
      t.integer :itemid, null: false, index: true
      t.string :slug, null: false
      t.string :url, null: false
      t.references :asset, null: false, foreign_key: true

      t.timestamps
    end
  end
end
