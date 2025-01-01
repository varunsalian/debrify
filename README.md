# Debrify

![License](https://img.shields.io/badge/license-MIT-blue.svg) ![Version](https://img.shields.io/badge/version-1.0.0-green.svg)

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Commands](#commands)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Overview

**Debrify** is a Python-based command-line application designed to help users efficiently search and add torrent magnets to Real Debrid. It focuses exclusively on adding cached torrents to Real Debrid for instant availability.

Debrify utilizes a local database created with **DuckDB**, populated from the open-source **torrentcsv** dataset. This approach enables fast and reliable torrent searches. When adding a torrent magnet, the tool attempts to add the largest file in the magnet to Real Debrid. If the file is not cached and instantly available, it will not be added, ensuring only ready-to-stream files are processed.

## Features

- **Search Torrents**: Quickly search for torrents using keywords from the locally created database.
- **Batch Add Torrents**: Add all torrents matching a specific keyword or phrase to Real Debrid in one go.
- **Selective Range Adding**: Choose a specific range of results when adding torrents to Real Debrid, providing better control over what is added.
- **Efficient Database Handling**: Uses DuckDB for fast and optimized database queries based on the torrentcsv dataset.
- **Cached Torrents Only**: Ensures only instantly available torrents are added to Real Debrid, improving user experience.

## Installation

### For Developers

1. Clone the repository:
   ```bash
   git clone https://github.com/varunsalian/debrify.git
   cd debrify
   ```

2. Install the application (Make sure you have python 3.8 or above):
   ```bash
   pip install .
   ```
      ```bash
   debrify --help
   ```
   Refer to the [Usage](#usage) and [Commands](#commands) sections for available commands.

      OR

   Run the application directly:
   ```bash
   python main.py --help
   ```
   Refer to the [Usage](#usage) and [Commands](#commands) sections for available commands.

### For Users

### On Windows, macOS, and Linux

1. Download the appropriate release for your operating system from the links below:

   - **Windows x86**: [Download](https://github.com/varunsalian/debrify/releases/download/windows-x86-6/debrify-windows-x86.zip)
   - **Windows x64**: [Download](https://github.com/varunsalian/debrify/releases/download/windows-x64-6/debrify-windows-x64.zip)
   - **Mac x86_64**: [Download](https://github.com/varunsalian/debrify/releases/download/mac-x86_64-6/debrify-mac-x86_64.zip)
   - **Mac arm64**: [Download](https://github.com/varunsalian/debrify/releases/download/mac-arm64-6/debrify-mac-arm64.zip)
   - **Linux x86**: [Download](https://github.com/varunsalian/debrify/releases/download/linux-x86-19/debrify-linux-x86.zip)
   - **Linux x64**: [Download](https://github.com/varunsalian/debrify/releases/download/linux-x64-19/debrify-linux-x64.zip)

2. Unzip the downloaded file.

3. Open a terminal or command prompt in the extracted folder.

4. Run the following command:
   ```bash
   ./main --help
   ```
   Refer to the [Usage](#usage) and [Commands](#commands) sections for available commands.

### On Android

1. Install Termux from the [Google Play Store](https://play.google.com/store/apps/details?id=com.termux&hl=en_IN&pli=1) OR [Download APK and Install](https://github.com/termux/termux-app/releases/download/v0.118.1/termux-app_v0.118.1+github-debug_universal.apk)
2. Open Termux and update the package list:
   ```bash
   pkg update
   ```
3. Install Python within Termux:
   ```bash
   pkg install python
   ```
4. Install Debrify using pip:
   ```bash
   pip install debrify
   ```
5. Run Debrify using:
   ```bash
   debrify --help
   ```
   Refer to the [Usage](#usage) and [Commands](#commands) sections for available commands.

This process allows you to efficiently run Debrify on Android devices.


## Usage

**<span style='color: orange;'>Note:</span>** **If you have downloaded the release(for windows, mac, linux) , use `./main` instead of `debrify` for the following commands.**

1. **Update the Database**:
   ```bash
   debrify --force-update
   ```
   This updates the local database with the latest data from the torrentcsv dataset.

2. **Set Real Debrid API Key**:
   Obtain your Real Debrid API key from [Real Debrid API Token](https://real-debrid.com/apitoken) and set it:
   ```bash
   debrify --set-debrid-api-key YOUR_DEBRID_API_KEY
   ```

3. **Add Torrents Based on Keywords**:
   To add all torrents matching specified keywords to your Real Debrid account:
   ```bash
   debrify --keywords keyword1, keyword2
   ```

4. **List Torrents Without Adding**:
   To list torrents matching specific keywords without adding them to Real Debrid:
   ```bash
   debrify --keywords keyword1 --download-to-debrid false
   ```

5. **Add Torrents in a Specific Range**:
   After listing torrents, you can specify a range to add:
   ```bash
   debrify --keywords keyword1 --download-range 0-100
   ```
   This will attempt to check and add cached torrents from the specified range.

## Commands

- `--force-update`: Deletes the existing database and updates it with the latest data from torrentcsv.
  ```bash
  debrify --force-update
  ```
- `--set-debrid-api-key`: Sets the Real Debrid API key for your account.
  ```bash
  debrify --set-debrid-api-key YOUR_DEBRID_API_KEY
  ```
- `--keywords`: Specifies keywords to search in the database. Keywords can be comma-separated, and space within groups is preserved.
  ```bash
  debrify --keywords keyword1, keyword2
  ```
- `--download-to-debrid`: Specifies whether to attempt adding torrents to Real Debrid. Accepts `true` or `false`.
  ```bash
  debrify --keywords keyword1 --download-to-debrid false
  ```
- `--download-range`: Specifies a range of results (start-end) to attempt adding to Real Debrid.
  ```bash
  debrify --keywords keyword1 --download-range 0-100
  ```
- `--print-results`: Enables or disables printing of results. Accepts `true` or `false`.
  ```bash
  debrify --keywords keyword1 --print-results true
  ```
- `-v` or `--version`: Displays the current version of the application.
  ```bash
  debrify -v
  ```

## Examples

1. **Update the Database**:
   ```bash
   debrify --force-update
   ```
   Updates the local database with the latest data from the torrentcsv dataset.

2. **Set Real Debrid API Key**:
   ```bash
   debrify --set-debrid-api-key YOUR_DEBRID_API_KEY
   ```
   Sets the Real Debrid API key for the application.

3. **Add Torrents Based on Keywords**:
   ```bash
   debrify --keywords ubuntu
   ```
   Adds all torrents matching the keyword "ubuntu" to your Real Debrid account.

4. **List Torrents Without Adding**:
   ```bash
   debrify --keywords ubuntu --download-to-debrid false
   ```
   Lists all torrents matching the keyword "ubuntu" without adding them to Real Debrid.

5. **Add Torrents in a Specific Range**:
   ```bash
   debrify --keywords ubuntu --download-range 0-100
   ```
   Adds cached torrents from the search results for "ubuntu" in the specified range (0-100).

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository.
2. Create a new branch for your feature or bug fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes and commit them:
   ```bash
   git commit -m "Add your feature description"
   ```
4. Push to your branch:
   ```bash
   git push origin feature/your-feature-name
   ```
5. Open a pull request and describe your changes.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **torrentcsv**: For providing the open-source dataset used to build the database.
- **DuckDB**: For its powerful and efficient database capabilities.
- **Real Debrid**: For enabling seamless torrent management.
- **rd-api-py**: For providing wrapper for the real debrid APIs
- The open-source community for their invaluable contributions and support.

