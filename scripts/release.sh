#!/bin/bash

# Release script for electron-liquid-glass
# Usage: ./scripts/release.sh [patch|minor|major|prerelease]

set -e

RELEASE_TYPE=${1:-patch}

echo "🚀 Starting release process..."
echo "Release type: $RELEASE_TYPE"

# Check if we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "❌ Error: Must be on main branch to release. Current branch: $CURRENT_BRANCH"
  exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ Error: Working directory is not clean. Please commit or stash changes."
  exit 1
fi

# Pull latest changes
echo "📥 Pulling latest changes..."
git pull origin main

# Clean and build
echo "🧹 Cleaning previous builds..."
bun run clean

echo "🔨 Building native module..."
bun run build:native

echo "📦 Building TypeScript library..."
bun run build

# Run tests
echo "🧪 Running tests..."
node -e "
  try {
    require('./dist/index.cjs');
    console.log('✅ CJS build works');
  } catch (err) {
    if (!err.message.includes('NSViewFrameDidChangeNotification')) {
      throw err;
    }
    console.log('✅ CJS build works (expected native error)');
  }
"

# Version bump
echo "📈 Bumping version..."
OLD_VERSION=$(node -p "require('./package.json').version")
npm version $RELEASE_TYPE --no-git-tag-version
NEW_VERSION=$(node -p "require('./package.json').version")

echo "Version: $OLD_VERSION → $NEW_VERSION"

# Update changelog
echo "📝 Updating changelog..."
DATE=$(date +%Y-%m-%d)
sed -i '' "s/## \[Unreleased\]/## [Unreleased]\n\n## [$NEW_VERSION] - $DATE/" CHANGELOG.md

# Commit changes
echo "💾 Committing changes..."
git add package.json CHANGELOG.md
git commit -m "chore: bump version to $NEW_VERSION"

# Create tag
echo "🏷️  Creating tag..."
git tag "v$NEW_VERSION"

# Push changes
echo "📤 Pushing changes..."
git push origin main
git push origin "v$NEW_VERSION"

echo "✅ Release $NEW_VERSION completed!"
echo "🎉 Check GitHub Actions for automated publishing: https://github.com/meridius-labs/electron-liquid-glass/actions" 