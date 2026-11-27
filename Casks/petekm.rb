cask "petekm" do
  version "1.1.2"
  sha256 "30a53b1bf37c1d901b73b85e36bd8dd91bb17bace0868cc65151793f135b06db"

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
