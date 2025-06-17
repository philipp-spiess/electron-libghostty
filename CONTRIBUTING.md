# Contributing to electron-liquid-glass

Thank you for your interest in contributing! This guide will help you get started.

## Development Setup

### Prerequisites

- **macOS** (required for native development)
- **Node.js** 18+
- **Bun** (preferred package manager)
- **Xcode Command Line Tools**

### Getting Started

1. **Fork and clone the repository**

   ```bash
   git clone https://github.com/your-username/electron-liquid-glass.git
   cd electron-liquid-glass
   ```

2. **Install dependencies**

   ```bash
   bun install
   ```

3. **Build the native module**

   ```bash
   bun run build:native
   ```

4. **Build the TypeScript library**

   ```bash
   bun run build
   ```

5. **Run the example**
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
