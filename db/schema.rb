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

ActiveRecord::Schema[8.0].define(version: 2025_09_30_142319) do
  create_table "asset_urls", force: :cascade do |t|
    t.string "url"
    t.integer "asset_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_asset_urls_on_asset_id"
    t.index ["url"], name: "index_asset_urls_on_url", unique: true
  end

  create_table "asset_urls_webpages", force: :cascade do |t|
    t.integer "webpage_id"
    t.integer "asset_url_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_url_id"], name: "index_asset_urls_webpages_on_asset_url_id"
    t.index ["webpage_id", "asset_url_id"], name: "index_asset_urls_webpages_on_webpage_id_and_asset_url_id", unique: true
    t.index ["webpage_id"], name: "index_asset_urls_webpages_on_webpage_id"
  end

  create_table "assets", force: :cascade do |t|
    t.string "type", null: false
    t.integer "website_id", null: false
    t.string "status"
    t.integer "assetid", null: false
    t.string "asset_type", null: false
    t.string "name", null: false
    t.string "short_name", null: false
    t.string "canonical_url"
    t.string "redirect_url"
    t.string "content_html"
    t.string "digest"
    t.datetime "squiz_updated"
    t.string "squiz_breadcrumbs"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assetid"], name: "index_assets_on_assetid", unique: true
    t.index ["canonical_url"], name: "index_assets_on_canonical_url"
    t.index ["website_id"], name: "index_assets_on_website_id"
  end

  create_table "pdfs", force: :cascade do |t|
    t.integer "website_id", null: false
    t.string "url"
    t.integer "size", null: false
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["website_id"], name: "index_pdfs_on_website_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "firstname", null: false
    t.string "lastname", null: false
    t.string "password", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "webpages", force: :cascade do |t|
    t.integer "website_id", null: false
    t.integer "asset_id", null: false
    t.string "status", null: false
    t.float "spider_duration"
    t.string "content"
    t.string "checksum"
    t.string "squiz_canonical_url"
    t.datetime "squiz_updated"
    t.string "squiz_breadcrumbs"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_webpages_on_asset_id"
    t.index ["squiz_canonical_url"], name: "index_webpages_on_squiz_canonical_url"
    t.index ["website_id"], name: "index_webpages_on_website_id"
  end

  create_table "websites", force: :cascade do |t|
    t.string "name", null: false
    t.string "url", null: false
    t.integer "root_webpage_id"
    t.boolean "auto_refresh", default: false
    t.integer "refresh_period", default: 86400
    t.string "output_root"
    t.string "publish_url"
    t.string "status", default: "unscraped", null: false
    t.string "remove_scripts", default: ""
    t.string "css", default: ""
    t.string "javascript", default: ""
    t.string "notes", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_webpage_id"], name: "index_websites_on_root_webpage_id"
  end

  add_foreign_key "asset_urls", "assets"
  add_foreign_key "asset_urls_webpages", "asset_urls"
  add_foreign_key "asset_urls_webpages", "webpages"
  add_foreign_key "assets", "websites"
  add_foreign_key "pdfs", "websites"
  add_foreign_key "webpages", "assets"
  add_foreign_key "webpages", "websites"
  add_foreign_key "websites", "webpages", column: "root_webpage_id"
end
