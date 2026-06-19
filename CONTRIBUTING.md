# Contributing to LocalSend 🚀

Thank you for your interest in contributing to LocalSend! This guide will help you get started, whether you're a developer, translator, or documentation writer.

**Table of Contents**
- [🎯 First Contribution? Start Here!](#first-contribution)
- [📋 Ways to Contribute](#ways-to-contribute)
- [💻 Contributing Code](#contributing-code)
- [🌍 Translating](#translating)
- [📝 Improving Documentation](#improving-documentation)
- [🐛 Bug Reports & Feature Requests](#bug-reports--feature-requests)
- [📦 Distribution](#distribution)
- [✅ Contribution Guidelines](#contribution-guidelines)
- [❓ Troubleshooting](#troubleshooting)
- [🔒 Security Issues](#security-issues)

---

## 🎯 First Contribution? Start Here!

Welcome! Here's a simple checklist to make your first contribution:

### ✅ Step 1: Set Up Git
```bash
# Configure your identity
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Generate a Personal Access Token (PAT) on GitHub:
# 1. Go to https://github.com/settings/tokens
# 2. Click "Generate new token (classic)"
# 3. Select "repo" scope
# 4. Copy the token (starts with ghp_)
```

### ✅ Step 2: Fork & Clone
```bash
# 1. Fork the repository on GitHub (click "Fork" button)
# 2. Clone YOUR fork
git clone https://github.com/YOUR_USERNAME/localsend.git
cd localsend
```

### ✅ Step 3: Choose a Simple Task
**New to open source?** Start with one of these:
- 📝 Fix a typo in documentation
- 🌍 Add missing translations
- 🐛 Fix a small bug (look for "good first issue" label)

### ✅ Step 4: Make Your Changes
```bash
# Create a new branch
git checkout -b fix/typo-in-readme

# Make your changes...
# Test them...

# Commit your changes
git add .
git commit -m "fix: correct typo in README.md"
```

### ✅ Step 5: Push & Create PR
```bash
# Push to your fork
git push origin fix/typo-in-readme

# Go to GitHub and create a Pull Request
# (GitHub will show a "Compare & pull request" button)
```

**That's it!** 🎉 Maintainers will review your PR and provide feedback.

---

## 📋 Ways to Contribute

You don't need to be a programmer to contribute! Here are all the ways you can help:

| Type | Skills Needed | Difficulty | Impact |
|------|---------------|------------|---------|
| 🌍 **Translation** | Foreign language | ⭐ Easy | 🌍 Global reach |
| 📝 **Documentation** | Writing | ⭐ Easy | 📚 Better onboarding |
| 🐛 **Bug Fixes** | Dart/Flutter | ⭐⭐ Medium | 🛠️ Stability |
| ✨ **New Features** | Dart/Flutter | ⭐⭐⭐ Hard | 🚀 Innovation |
| 📦 **Packaging** | Linux/DevOps | ⭐⭐ Medium | 📦 Easy installation |
| 🧪 **Testing** | Dart/Flutter | ⭐⭐ Medium | ✅ Quality |

---

## 💻 Contributing Code

### Prerequisites

Before you start coding, make sure you have:
- ✅ [Flutter SDK](https://flutter.dev/get-started) (check `.fvmrc` for required version)
- ✅ [FVM](https://fvm.app) (Flutter Version Manager) - *recommended*
- ✅ [Rust](https://www.rust-lang.org/tools/install) (for native modules)
- ✅ Git

### Step-by-Step Setup

#### 1️⃣ Install Flutter via FVM (Recommended)
```bash
# Install FVM
dart pub global activate fvm

# Use the correct Flutter version for this project
cd localsend
fvm install
fvm use
```

#### 2️⃣ Install Dependencies
```bash
cd app
fvm flutter pub get
dart run build_runner build -d
```

#### 3️⃣ Run the App
```bash
# Debug mode (hot reload enabled)
fvm flutter run

# Release mode (faster, no hot reload)
fvm flutter run --release
```

#### 4️⃣ Make Your Changes
- 📝 **Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)**
- 🧪 **Write tests** for your changes
- 📝 **Document your code** (especially public APIs)

#### 5️⃣ Test Your Changes
```bash
# Run all tests
fvm flutter test

# Run tests with coverage
fvm flutter test --coverage

# Check code formatting
fvm flutter format --set-exit-if-changed .
```

#### 6️⃣ Commit & Push
```bash
# Stage your changes
git add .

# Commit with a descriptive message
git commit -m "feat: add dark mode support for settings page"

# Push to your fork
git push origin your-branch-name
```

#### 7️⃣ Create a Pull Request
- Go to https://github.com/YOUR_USERNAME/localsend
- Click "Compare & pull request"
- Fill in the PR template
- Link any related issues

---

## 🌍 Translating

Help make LocalSend available in more languages!

### Method 1: Using Weblate (Easiest) ⭐⭐⭐

1. Go to [Weblate Translation Platform](https://hosted.weblate.org/projects/localsend/app)
2. Create an account or log in
3. Select a language
4. Translate the missing strings
5. Done! No coding required!

### Method 2: Manual Translation (For Developers)

#### Step 1: Fork & Clone
```bash
git clone https://github.com/YOUR_USERNAME/localsend.git
cd localsend/app/assets/i18n
```

#### Step 2: Choose What to Do
You have three options:

**Option A: Add Missing Translations**
```bash
# Edit the missing translations file for your language
notepad _missing_translations_<locale>.json
```

**Option B: Fix Existing Translations**
```bash
# Edit the main translation file
notepad strings_<locale>.i18n.json
```

**Option C: Add a New Language**
```bash
# 1. Find your locale code: https://saimana.com/list-of-country-locale-code/
# 2. Create new files:
#    - strings_<locale>.i18n.json
#    - _missing_translations_<locale>.json
# 3. Add the locale to lib/i18n.dart
```

#### Step 3: Translate the Strings
Here's an example of a translation file:

```json
{
  "locale": "Français",
  "appName": "LocalSend",
  "general": {
    "accept": "Accepter",
    "cancel": "Annuler",
    "confirm": "Confirmer"
  }
}
```

**⚠️ Important Notes:**
- Fields starting with `@` are comments, **don't translate them**
- Use `"@:general.accept"` to reference other translations
- Test your translations (see Step 4)

#### Step 4: Test Your Translations
```bash
cd app

# Update translations
fvm flutter pub run slang

# Run the app
fvm flutter run

# Switch to your language in Settings to verify
```

#### Step 5: Submit Your Changes
```bash
git add .
git commit -m "feat(i18n): add French translations"
git push origin main
```

Then create a Pull Request!

---

## 📝 Improving Documentation

Good documentation helps everyone! Here's how you can help:

### What to Improve
- ✅ Fix typos and grammar errors
- ✅ Add missing information to README.md
- ✅ Improve code comments
- ✅ Write tutorials or guides
- ✅ Add examples to CONTRIBUTING.md (this file!)

### How to Contribute

#### 1️⃣ Identify What to Improve
- Read through the docs
- Note any unclear sections
- Check for outdated information

#### 2️⃣ Make Your Changes
```bash
# Edit the file(s)
notepad README.md
notepad CONTRIBUTING.md

# Or use a Markdown editor for better experience
```

#### 3️⃣ Preview Your Changes (Optional but Recommended)
Use a Markdown previewer:
- **VS Code**: Right-click → "Open Preview"
- **Online**: https://stackedit.io/
- **命令行**: `grip README.md` (requires `pip install grip`)

#### 4️⃣ Commit & Push
```bash
git add .
git commit -m "docs: improve installation instructions in README"
git push origin main
```

#### 5️⃣ Create a Pull Request
- Describe what you improved and why
- Add screenshots if applicable

---

## 🐛 Bug Reports & Feature Requests

### Before You Report...

**🔍 Search existing issues first!** Your issue might already be reported.

→ Go to https://github.com/localsend/localsend/issues

### Reporting a Bug

**Use the Bug Report Template** when creating a new issue.

**Include:**
- ✅ **Steps to reproduce** (be specific!)
- ✅ **Expected behavior**
- ✅ **Actual behavior**
- ✅ **Screenshots** (if applicable)
- ✅ **Environment** (OS, app version, device model)
- ✅ **Logs** (if available)

**Example Bug Report:**
```markdown
## Bug: App crashes when selecting large files

### Steps to Reproduce
1. Open LocalSend
2. Click "Send"
3. Select a 5GB file
4. Click "Send"

### Expected Behavior
File should start transferring

### Actual Behavior
App crashes immediately

### Environment
- OS: Windows 11
- App Version: 1.15.0
- Device: Dell XPS 13

### Logs
[Attach crash logs if available]
```

### Requesting a Feature

**Use the Feature Request Template.**

**Include:**
- ✅ **Clear description** of the feature
- ✅ **Use case** (why is it needed?)
- ✅ **Mockups/screenshots** (if applicable)
- ✅ **Alternatives considered**

---

## 📦 Distribution

Help spread LocalSend to more platforms!

### Current Status

We're looking for help with:
- ❌ Traditional Linux distributions (Debian, Fedora, Arch, etc.)
- ❌ More package managers
- ❌ Your idea here!

### How to Help

#### 1️⃣ Package for a New Platform
Example: Packaging for Debian/Ubuntu

```bash
# 1. Create a .deb package
# 2. Test the package
# 3. Submit to the official repo or create a PPA
# 4. Update this CONTRIBUTING.md with instructions
```

#### 2️⃣ Update This Document
Once you've successfully packaged LocalSend, please update the [Distribution](#distribution) section above with:
- ✅ Platform name
- ✅ Installation command
- ✅ Maintainer info
- ✅ Link to package repository

#### 3️⃣ Create an Issue
If you're working on a new platform, create an issue to let others know:
```
Title: Package LocalSend for Debian
Description: I'm working on creating a .deb package for Debian/Ubuntu...
```

---

## ✅ Contribution Guidelines

To ensure a smooth review process, please follow these guidelines:

### 📝 Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

**Examples:**
```bash
feat: add dark mode support
fix(i18n): correct Spanish translation for 'cancel'
docs: update README with troubleshooting section
chore: upgrade dependencies to latest versions
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### 🧪 Code Quality

- ✅ **Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)**
- ✅ **Run the formatter**: `fvm flutter format .`
- ✅ **Run the analyzer**: `fvm flutter analyze`
- ✅ **Write tests** for new features and bug fixes
- ✅ **Keep commits focused** (one logical change per commit)

### 📦 Pull Request Guidelines

- ✅ **Target the `main` branch**
- ✅ **Fill out the PR template** completely
- ✅ **Link related issues** (`Closes #123`, `Fixes #456`)
- ✅ **Add screenshots** for UI changes
- ✅ **Keep PRs focused** (don't mix unrelated changes)
- ✅ **Be responsive** to review feedback

---

## ❓ Troubleshooting

### Common Issues

#### "Flutter version mismatch"
**Problem:** The project requires a specific Flutter version.

**Solution:**
```bash
# Use FVM to install the correct version
fvm install
fvm use

# Verify
fvm flutter --version
```

#### "Build failed with exception"
**Problem:** Gradle/Maven build failure.

**Solution:**
```bash
# Clean and rebuild
cd app
fvm flutter clean
fvm flutter pub get
fvm flutter run
```

#### "Translation not showing up"
**Problem:** You added translations but they don't appear in the app.

**Solution:**
```bash
cd app

# Regenerate translations
fvm flutter pub run slang

# Restart the app (hot reload won't work)
# Stop the app (q)
fvm flutter run
```

#### "Git push fails with authentication error"
**Problem:** GitHub requires a Personal Access Token (PAT).

**Solution:**
1. Create a PAT: https://github.com/settings/tokens
2. Use the token as your password when pushing
3. Or use the GitHub CLI: `gh auth login`

#### "App not discovering devices"
**Problem:** LocalSend can't find other devices.

**Solution:**
1. Ensure all devices are on the same Wi-Fi network
2. Disable AP isolation on your router
3. Allow port 53317 in your firewall
4. On Windows, set network to "Private"
5. On macOS/iOS, enable "Local Network" permission

---

## 🔒 Security Issues

**⚠️ DO NOT report security issues publicly!**

If you discover a security vulnerability:
1. ✅ **Email us directly**: [support@localsend.org](mailto:support@localsend.org)
2. ✅ **Do NOT create a public issue**
3. ✅ **Include detailed information** about the vulnerability
4. ✅ **Wait for our response** (we'll acknowledge within 48 hours)

We'll work with you to fix the issue before making it public.

---

## 🎉 Thank You!

Every contribution, no matter how small, makes LocalSend better for everyone. Thank you for being part of our community! 🚀

**Questions?** Feel free to:
- 💬 Join our [Discord](https://discord.gg/GSRWmQNP87)
- 📧 Email us at [support@localsend.org](mailto:support@localsend.org)
- 🐛 Open an issue (for non-security bugs)

---

**Happy Contributing!** 🎊
