---
name: Add Site
description: Create a new site configuration, update the manifest, and fetch icons.
---

# Add New Site Skill

This skill automates the process of adding a new site to the application. It generates a configuration file based on a template, updates the sites manifest, and fetches the site icon.

## Prerequisites

- Python 3 must be installed.
- Dart must be installed.

## Input

The skill requires the following inputs from the user (you should ask for these if not provided):

- **site_type**: The type of the site (e.g., `NexusPHP`, `M-Team`, `NexusPHPWeb`).
- **site_id**: A unique identifier for the site (e.g., `example_site`).
- **site_url**: The primary URL of the site (e.g., `https://example.com/`).
- **site_name** (Optional): The display name of the site. If not provided, `site_id` will be used.

## Steps

### 1. Generate Site Configuration

Run the python script to generate the JSON configuration file.

```bash
python3 .agent/skills/add_site/scripts/generate_site_config.py \
  "{site_id}" \
  "{site_url}" \
  "{site_type}" \
  --name "{site_name}" \
  --template_file "assets/site_configs.json" \
  --output_dir "assets/sites"
```

> **Note**: If `site_name` is not provided, omit the `--name` argument.

### 2. Update Sites Manifest

Run the existing shell script to update the `assets/sites_manifest.json` file.

```bash
bash generate_sites_manifest.sh
```

### 3. Fetch Site Icon

Run the Dart script to fetch and update the site icon.

```bash
dart run tool/fetch_site_icons.dart
```

## Verification

After running the steps, verifying the following:
1. Check that `assets/sites/{site_id}.json` exists and contains correct information.
2. Check that `assets/sites_manifest.json` includes the new json file.
3. Check if the icon was successfully downloaded (check output of the dart command).
