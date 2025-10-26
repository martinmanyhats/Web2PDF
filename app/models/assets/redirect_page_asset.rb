# frozen_string_literal: true

class RedirectPageAsset < Asset
  def redirect_url=(url)
    # p "!!! RedirectPageAsset:redirect_url= #{url}"
    redirect_uri = URI.parse(url)
    raise "RedirectPageAsset:create_asset_urls missing scheme for redirection #{url}" unless redirect_uri.scheme
    raise "RedirectPageAsset:create_asset_urls missing host for redirection #{url}" unless redirect_uri.host
    raise "RedirectPageAsset:create_asset_urls missing path for redirection #{url}" unless redirect_uri.path
    # Don't call super as that will raise.
    write_attribute(:redirect_url, url)
  end

  def resolve_redirection
    p "!!! RedirectPageAsset:resolve_redirection redirect_url #{redirect_url}"
    depth = 0
    loop do
      if website.internal?(redirect_url)
        target_asset = Asset.asset_for_uri(URI.parse(website, redirect_url))
        p "!!! RedirectPageAsset:resolve_redirection target_asset #{target_asset.inspect}"
        redirect_url = target_asset.canonical_url
        raise "RedirectPageAsset:resolve_redirection missing canonical_url asset #{asset.inspect}" if redirect_url.empty?
        unless target_asset.is_a?(RedirectPageAsset)
          p "!!! RedirectPageAsset:resolve_redirection resolved #{target_asset.redirect_url}"
          save!
          break
        end
        p "!!! RedirectPageAsset:resolve_redirection indirecting"
      else
        p "!!! RedirectPageAsset:resolve_redirection not internal #{url}"
        break
      end
      depth += 1
      raise "RedirectPageAsset:resolve_redirection redirect depth exceeded" if depth > 5
    end
  end
end
