assets = "#{Rails.root}/app/models/assets"
Rails.autoloaders.main.collapse(assets) # Not a namespace.

unless Rails.application.config.eager_load
  Rails.application.config.to_prepare do
    Rails.autoloaders.main.eager_load_dir(assets)
  end
end