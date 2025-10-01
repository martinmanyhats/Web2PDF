class WebpageParent < ActiveRecord::Migration[8.0]
  def change
    create_table :webpage_parents do |t|
      t.references :webpage, foreign_key: true
      t.references :parent, foreign_key: { to_table: :webpages }

      t.timestamps
    end
  end
end
