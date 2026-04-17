class CreateWordpressItems < ActiveRecord::Migration[8.1]
  def change
    create_table :wordpress_items do |t|
      t.string :itemid
      t.references :asset, null: false, foreign_key: true
      t.string :slug
      t.string :url

      t.timestamps
    end
  end
end
