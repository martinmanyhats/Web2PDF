class CreateWebsites < ActiveRecord::Migration[8.0]
  def change
    create_table :websites do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.references :root_webpage, foreign_key: { to_table: :webpages}
      t.boolean :auto_refresh, default: false
      t.integer :refresh_period, default: 60 * 60 * 24
      t.string :publish_url
      t.string :status, null: false, default: "unscraped"
      t.string :remove_scripts, default: ""
      t.string :additional_css, default: ""
      t.string :additional_js, default: ""
      t.string :notes, default: ""

      t.timestamps
    end
  end
end
