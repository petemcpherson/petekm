cask "petekm" do
  version "1.0.0"
  sha256 "620a590cfe9a05e373b1b2edbd3f9e5df4d6444aab4f0163cf679a4b3859659f"

  url "https://github.com/petemcpherson/petekm/releases/download/v#{version}/PeteKM-#{version}.dmg"
  name "PeteKM"
  desc "Markdown daily notes and personal library"
  homepage "https://github.com/petemcpherson/petekm"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "PeteKM.app"

  zap trash: [
    "~/Library/Application Support/PeteKM",
    "~/Library/Caches/com.petekm.PeteKM",
    "~/Library/Preferences/com.petekm.PeteKM.plist",
  ]
end
