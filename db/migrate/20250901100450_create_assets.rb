class CreateAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :assets do |t|
      t.string :type, null: false
      t.references :website, null: false, foreign_key: true
      t.integer :assetid, null: false, index: { unique: true }
      t.string :asset_type, null: false
      t.string :name, null: false
      t.string :short_name, null: false
      t.string :redirect_url
      t.string :digest

      t.timestamps
    end
  end
end
