import os
import yaml

def delete_file_if_exists(filename):
    """Delete a file if it exists."""
    if os.path.exists(filename):
        os.remove(filename)
        print(f"Deleted existing file: {filename}")
    else:
        print(f"File does not exist, skipping deletion: {filename}")

def get_absoulute_path(file_path):
    return os.path.join(get_project_root(), file_path)

def get_project_root():
    package_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(package_dir)

def load_config():
    """
    Load configuration from a hardcoded YAML file path.
    """

    config_path = get_absoulute_path('config/config.yaml')
    try:
        with open(config_path, 'r') as file:
            return yaml.safe_load(file)
    except FileNotFoundError:
        print(f"Error: Configuration file not found at {config_path}.")
        exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Failed to parse YAML file. Details: {e}")
        exit(1)
