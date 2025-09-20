# Contributing to electron-liquid-glass

Thank you for your interest in contributing! This guide will help you get started.

## Development Setup

### Prerequisites

- **macOS** (required for native development)
- **Node.js** 18+
- **Bun** (preferred package manager)
- **Zig** **0.14.0** or newer (libghostty minimum)
- **Xcode Command Line Tools** (for `clang`, `lipo`, `dsymutil`, Metal headers)
- **CMake** and **Ninja** (only needed when rebuilding libghostty vendor dependencies)

> ℹ️ After installing Zig, warm its cache once with `zig fetch --global-cache-dir ~/.cache/zig` so subsequent libghostty builds avoid repeated downloads.

### Getting Started

1. **Fork and clone the repository**

   ```bash
   git clone https://github.com/your-username/electron-liquid-glass.git
   cd electron-liquid-glass
   ```

2. **Initialize submodules**

   ```bash
   git submodule update --init --recursive
   ```

3. **Install dependencies**

   ```bash
   bun install
   ```

4. **Build the native module**

   ```bash
   bun run build:native
   ```

5. **Build the TypeScript library**

   ```bash
   bun run build
   ```

6. **Run the example**
   ```bash
   bun run dev
   ```

## Development Workflow

### Making Changes

1. **Create a feature branch**

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**

   - Follow the existing code style
   - Add comments for complex logic
   - Update TypeScript types as needed

3. **Test your changes**

   ```bash
   bun run build:all
   bun run dev  # Test with the example app
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

### Commit Message Format

We follow [Conventional Commits](https://conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

### Pull Request Process

1. **Push your branch**

   ```bash
   git push origin feature/your-feature-name
   ```

2. **Create a Pull Request**

   - Use the PR template
   - Provide clear description of changes
   - Include screenshots if applicable
   - Link any related issues

3. **Code Review**
   - Address feedback promptly
   - Keep discussions constructive
   - Update your branch as needed

## Code Style

- **TypeScript** for all new code
- **ESLint** for linting (when configured)
- **Prettier** for formatting (when configured)
- **JSDoc** comments for public APIs

## Testing

- Test on macOS (required)
- Test with multiple Electron versions when possible
- Include both ESM and CJS usage in tests
- Test the example application

## Native Development

### Libghostty Submodule

- The upstream Ghostty embedding API is vendored at `third_party/libghostty`.
- Track changes by updating the submodule: `git submodule update --remote --merge third_party/libghostty`.
- Record the upstream commit hash bump in `CHANGELOG.md` and explain any breaking API changes.

### Host Tooling Checklist

- Ensure `zig version` reports **0.14.0** or newer before running build scripts.
- Install Xcode command line tools (`xcode-select --install`) so `clang`, `lipo`, `dsymutil`, and Metal headers are present.
- Provide `CMake` and `ninja` when refreshing libghostty vendor dependencies (not needed for routine builds).
- Run `zig fetch --global-cache-dir ~/.cache/zig` once per machine to populate the cache and avoid repeated downloads.

### C++/Objective-C Guidelines

- Follow existing naming conventions
- Add proper error handling
- Use `RUN_ON_MAIN` macro for UI operations
- Document private API usage with comments

### Building Native Module

```bash
# Clean build
bun run clean
bun run build:native

# Debug build (with symbols)
npm run build:native -- --debug
```

## Release Process

Releases are automated via GitHub Actions, but you can also release manually:

```bash
# Patch release (0.1.0 → 0.1.1)
./scripts/release.sh patch

# Minor release (0.1.0 → 0.2.0)
./scripts/release.sh minor

# Major release (0.1.0 → 1.0.0)
./scripts/release.sh major
```

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/meridius-labs/electron-liquid-glass/issues)
- **Discussions**: [GitHub Discussions](https://github.com/meridius-labs/electron-liquid-glass/discussions)

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions.

---

Thank you for contributing! 🎉
