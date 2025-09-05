class CreateAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :assets do |t|
      t.integer :assetid, null: false, index: { unique: true }
      t.string :asset_type, null: false
      t.string :name, null: false
      t.string :short_name, null: false
      t.string :url, index: { unique: true }
      t.string :digest

      t.timestamps
    end
  end
end
