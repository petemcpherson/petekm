cask "petekm" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_DMG"

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
