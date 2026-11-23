cask "petekm" do
  version "1.1.1"
  sha256 "05eec6d60c085c88e5ed1d817257d8ee80132993c55179f1ff376ac51d4de074"

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
