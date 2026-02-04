
import argparse
import json
import os
import sys

def load_json(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(file_path, data):
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def main():
    parser = argparse.ArgumentParser(description='Generate site configuration JSON.')
    parser.add_argument('site_id', help='Unique identifier for the site')
    parser.add_argument('site_url', help='Primary URL of the site')
    parser.add_argument('site_type', help='Type of the site (e.g., NexusPHP, M-Team)')
    parser.add_argument('--name', help='Display name of the site (defaults to site_id)')
    parser.add_argument('--template_file', required=True, help='Path to site_configs.json')
    parser.add_argument('--output_dir', required=True, help='Directory to save the generated JSON')

    args = parser.parse_args()

    site_id = args.site_id
    site_url = args.site_url
    site_type = args.site_type
    site_name = args.name if args.name else site_id
    template_file = args.template_file
    output_dir = args.output_dir

    if not os.path.exists(template_file):
        print(f"Error: Template file not found: {template_file}")
        sys.exit(1)

    if not os.path.exists(output_dir):
        print(f"Error: Output directory not found: {output_dir}")
        sys.exit(1)

    # Output file path
    output_file = os.path.join(output_dir, f"{site_id}.json")
    if os.path.exists(output_file):
        print(f"Error: Site configuration already exists: {output_file}")
        sys.exit(1)

    # Load templates
    try:
        config_data = load_json(template_file)
        templates = config_data.get('defaultTemplates', {})
    except Exception as e:
        print(f"Error reading template file: {e}")
        sys.exit(1)

    if site_type not in templates:
        print(f"Error: Unknown site type '{site_type}'. Available types: {', '.join(templates.keys())}")
        sys.exit(1)

    # Create new config based on template
    template = templates[site_type]
    new_config = template.copy()
    
    # Update fields
    new_config['id'] = site_id
    new_config['name'] = site_name
    new_config['primaryUrl'] = site_url
    new_config['baseUrls'] = [site_url]
    new_config['siteType'] = site_type
    
    # Remove 'baseUrl' from template if it exists as we set 'baseUrls' and 'primaryUrl'
    if 'baseUrl' in new_config:
        del new_config['baseUrl']

    # Save to file
    try:
        save_json(output_file, new_config)
        print(f"Successfully generated configuration for {site_id} at {output_file}")
    except Exception as e:
        print(f"Error saving configuration file: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
