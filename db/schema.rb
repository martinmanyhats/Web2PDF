# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_10_22_131409) do
  create_table "asset_urls", force: :cascade do |t|
    t.integer "asset_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["asset_id"], name: "index_asset_urls_on_asset_id"
    t.index ["url"], name: "index_asset_urls_on_url", unique: true
  end

  create_table "assets", force: :cascade do |t|
    t.string "asset_type", null: false
    t.integer "assetid", null: false
    t.string "breadcrumbs_html"
    t.string "canonical_url"
    t.string "content_html"
    t.datetime "created_at", null: false
    t.string "digest"
    t.string "name", null: false
    t.string "redirect_url"
    t.string "short_name", null: false
    t.datetime "squiz_updated"
    t.string "status"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.integer "website_id", null: false
    t.index ["assetid"], name: "index_assets_on_assetid", unique: true
    t.index ["canonical_url"], name: "index_assets_on_canonical_url"
    t.index ["website_id"], name: "index_assets_on_website_id"
  end

  create_table "links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "destination_id", null: false
    t.integer "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_id"], name: "index_links_on_destination_id"
    t.index ["source_id", "destination_id"], name: "index_links_on_source_id_and_destination_id", unique: true
    t.index ["source_id"], name: "index_links_on_source_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "firstname", null: false
    t.string "lastname", null: false
    t.string "password", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
  end

  create_table "websites", force: :cascade do |t|
    t.boolean "auto_refresh", default: false
    t.datetime "created_at", null: false
    t.string "css", default: ""
    t.string "javascript", default: ""
    t.datetime "last_scraped"
    t.string "name", null: false
    t.string "notes", default: ""
    t.string "output_root_dir", null: false
    t.string "publish_url", null: false
    t.integer "refresh_period", default: 86400
    t.string "remove_scripts", default: ""
    t.datetime "updated_at", null: false
    t.string "url", null: false
  end

  add_foreign_key "asset_urls", "assets"
  add_foreign_key "assets", "websites"
  add_foreign_key "links", "assets", column: "destination_id"
  add_foreign_key "links", "assets", column: "source_id"
end
