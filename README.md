# PDF2MD

Convert PDFs to Markdown on macOS in three ways:

- command line with `pdf2md`
- Finder Quick Action with `Convert to Markdown`
- menu bar app that watches a folder for PDFs and converts them in the background

## Requirements

- macOS
- Apple Silicon build currently provided in releases
- Xcode command line tools if building from source

## Install

### Option 1: Download a release asset

From the [GitHub Releases](https://github.com/mweingartner/pdf2md/releases) page, download:

- `pdf2md-macos-arm64.tar.gz` for the CLI binary
- `PDF2MD-macos-arm64.zip` for the menu bar app

Example CLI install:

```bash
tar -xzf pdf2md-macos-arm64.tar.gz
install -m 755 pdf2md ~/.local/bin/pdf2md
```

Example app install:

```bash
ditto -x -k PDF2MD-macos-arm64.zip ~/Applications
```

### Option 2: Build from source

```bash
make verify
make install
```

That installs:

- `~/.local/bin/pdf2md`
- `~/Library/Services/Convert to Markdown.workflow`
- `~/Applications/PDF2MD.app`

## Usage

### CLI

```bash
pdf2md /path/to/file.pdf
```

### Finder Quick Action

1. Install with `make install`.
2. Right-click a PDF in Finder.
3. Choose `Quick Actions` > `Convert to Markdown`.

### Menu Bar App

1. Launch `PDF2MD.app`.
2. Choose:
   - a source folder to watch
   - an output folder for Markdown files
   - a processed folder to archive PDFs after conversion
3. Start monitoring.

The app uses macOS user-selected folder permissions. If you change folders, re-select them in the app.

## Release Packaging

To build release artifacts locally:

```bash
bash Scripts/package-release.sh
```

Artifacts are written to `dist/`.
