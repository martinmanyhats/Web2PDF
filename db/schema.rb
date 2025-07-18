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

ActiveRecord::Schema[8.0].define(version: 2025_07_03_181220) do
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
    t.integer "parent_id"
    t.string "title", default: "-"
    t.string "url", null: false
    t.string "page_path", null: false
    t.string "status", null: false
    t.float "scrape_duration"
    t.binary "content"
    t.string "checksum"
    t.string "squiz_canonical_url"
    t.string "squiz_assetid"
    t.string "squiz_short_name"
    t.datetime "squiz_updated"
    t.string "squiz_breadcrumbs"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_webpages_on_parent_id"
    t.index ["website_id"], name: "index_webpages_on_website_id"
  end

  create_table "websites", force: :cascade do |t|
    t.string "name", null: false
    t.string "url", null: false
    t.integer "root_webpage_id"
    t.boolean "auto_refresh", default: false
    t.integer "refresh_period", default: 86400
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

  add_foreign_key "pdfs", "websites"
  add_foreign_key "webpages", "webpages", column: "parent_id"
  add_foreign_key "webpages", "websites"
  add_foreign_key "websites", "webpages", column: "root_webpage_id"
end
