# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

website = Website.create(name: "Deddington History",
                         url: "https://www.deddingtonhistory.uk",
                         status: "unscraped",
                         remove_scripts: "cookieControl",
                         css: ""
)

# These assets don't get listed in Published Assets for some reason, possibly because they were previously Type 2 linked?
now = DateTime.now
Asset.create(assetid: 93, asset_type: "Asset Listing Page", name: "Home", short_name: "Home", url: "https://www.deddingtonhistory.uk/history", created_at: now, updated_at: now)
Asset.create(assetid: 121, asset_type: "Standard Page", name: "About DOL", short_name: "About DOL", url: "https://www.deddingtonhistory.uk/about", created_at: now, updated_at: now)
Asset.create(assetid: 415, asset_type: "Standard Page", name: "Disclaimer", short_name: "Disclaimer", url: "https://www.deddingtonhistory.uk/disclaimer", created_at: now, updated_at: now)
Asset.create(assetid: 419, asset_type: "Standard Page", name: "Feedback", short_name: "Feedback", url: "https://www.deddingtonhistory.uk/feedback", created_at: now, updated_at: now)
Asset.create(assetid: 9658, asset_type: "Standard Page", name: "Privacy Policy", short_name: "Privacy Policy", url: "https://www.deddingtonhistory.uk/privacy", created_at: now, updated_at: now)
