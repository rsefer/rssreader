# RSS Reader

rssreader is a SwiftUI app for iPhone, iPad, and macOS that connects to FreshRSS and presents your feed items with a two-pane reading workflow, inline content viewing, and read/unread management actions.

## Development

### Sparkle
Create a SPARKLE_PUBLIC_ED_KEY with Sparkle’s generate_keys tool, then store the public key in GitHub Actions secrets.

1. Make sure Sparkle is fetched once in Xcode (open project and run a build).
2. Locate generate_keys on your Mac by running: `find ~/Library/Developer/Xcode/DerivedData -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" -print -quit`
3. Run the tool: `/full/path/from/previous/step/generate_keys`
4. Copy the public key string it prints (base64 text).
5. Add that value as a repository secret with the name SPARKLE_PUBLIC_ED_KEY
