# PeteKM

A small, fast, native macOS app for capturing notes as plain Markdown files.

Press a global shortcut (⌃⌥Space by default) at any point in the day and you're back in the same document for **today**: your Daily Sticky. No titles, folders or tags while capturing. Later, your own AI agent (Claude Code, Codex, …) organizes what you wrote into a **Library** of long-lived Markdown files.

> Capture now. Organize later — mostly with AI.

- **Plain files you own.** Everything is `.md` in a folder you choose. No database, no account, no cloud service.
- **Daily Stickies are a permanent record.** The `daily/` folder is never rewritten by AI; only `library/` is.
- **Plays well with other editors.** VS Code, Claude Code and Finder can edit the same files at the same time.
- **Markdown stays visible.** Headings, bold and lists are styled live, with the `#`, `**` and `-` still showing.
- **Optional git sync** across Macs.
- **No AI inside the app.** PeteKM sets up the folder (`CLAUDE.md`, `AGENTS.md`, skills) so your agent knows the rules.

## Install

Requires macOS 26.2 or later.

```bash
brew tap petemcpherson/petekm https://github.com/petemcpherson/petekm
brew install --cask petemcpherson/petekm/petekm
```

Update with `brew upgrade`.

You can also download the `.dmg` from [Releases](https://github.com/petemcpherson/petekm/releases).

## Build from source

Requires Xcode 26.2 or later.

```bash
git clone https://github.com/petemcpherson/petekm.git
cd petekm
xcodebuild -scheme PeteKM -configuration Debug build
xcodebuild -scheme PeteKM test
```

Or open `PeteKM.xcodeproj` and run. Local builds sign to run locally with no setup. To sign with your own team, see `Config/Shared.xcconfig`.

Product and design docs live in [`context/`](context/). Start with [`context/map.md`](context/map.md).

## License

[MIT](LICENSE)
