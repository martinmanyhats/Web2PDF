class CreatePdfs < ActiveRecord::Migration[8.0]
  def change
    create_table :pdfs do |t|
      t.references :website, null: false, foreign_key: true
      t.string :url
      t.integer :size, null: false
      t.string :notes

      t.timestamps
    end
  end
end
