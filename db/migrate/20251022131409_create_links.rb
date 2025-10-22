class CreateLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :links do |t|
      t.references :source, null: false, foreign_key: {to_table: :assets }
      t.references :destination, null: false, foreign_key: {to_table: :assets }

      t.timestamps
    end
  end
end
