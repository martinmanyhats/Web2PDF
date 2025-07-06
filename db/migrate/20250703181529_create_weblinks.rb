class CreateWeblinks < ActiveRecord::Migration[8.0]
  def change
    create_table :weblinks do |t|
      t.references :from, null: false, foreign_key: { to_table: :webpages}
      t.references :to, null: false, foreign_key: { to_table: :webpages}
      t.string :linktype, null: false
      t.string :linkvalue, null: false
      t.string :info

      t.timestamps
    end
  end
end
