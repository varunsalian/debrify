import os
import yaml
import argparse
import sys
from debrify.services import TorrentDatabase, TorrentCSVDownloader

def parse_download_range(range_str):
    """Parse a range string (e.g., "1-200") into start and end integers."""
    try:
        start, end = map(int, range_str.split('-'))
        return start, end
    except ValueError:
        raise ValueError("Invalid range format. Use the format 'start-end'.")

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

def str2bool(value):
    """Convert string to boolean."""
    if isinstance(value, bool):
        return value
    if value.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif value.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        raise argparse.ArgumentTypeError('Boolean value expected.')


def preprocess_keywords(args):
    """
    Processes the arguments to handle --keywords flag.
    Comma separates keywords, and space within a comma-separated group stays intact.
    """
    combined_keywords = []
    temp = []

    for arg in args:
        if arg.startswith('--'):  # Stop processing on encountering a new flag
            if temp:
                combined_keywords.append(' '.join(temp))
            return combined_keywords, args[args.index(arg):]
        if ',' in arg:
            # Handle comma-separated keywords
            parts = arg.split(',')
            if temp:
                temp.append(parts[0])  # Add the first part to the current group
                combined_keywords.append(' '.join(temp))  # Complete the group
                temp = []  # Reset for the next group
            else:
                combined_keywords.append(parts[0])  # Add the first part directly
            # Add remaining parts as new keywords
            combined_keywords.extend(part.strip() for part in parts[1:] if part.strip())
        else:
            temp.append(arg)  # Collect space-separated words
    if temp:
        combined_keywords.append(' '.join(temp))  # Add the last group
    return combined_keywords, []


def load_configs(args):
    """Load the configuration and override with command-line arguments."""
    config = load_config()  # Assuming a method to load the config file

    if args.keywords:
        config['keywords'] = args.keywords
    if args.download_range is not None:
        config['download_range'] = args.download_range
    if args.download_to_debrid is not None:
        config['download_to_debrid'] = args.download_to_debrid
    if args.print_results is not None:
        config['print_results'] = args.print_results
    return config


def display_results(results_csv, keyword):
    """Display search results in a table."""
    from rich.console import Console
    from rich.table import Table

    console = Console()
    table = Table(title=f"Results for '{keyword}'")
    table.add_column("No.", style="cyan", justify="right")
    table.add_column("Data", style="magenta", justify="left")

    for index, data in enumerate(results_csv, start=0):
        table.add_row(f"{index:04}", data[1])

    console.print(table)

def parse_arguments():
    """Parse command-line arguments."""
    args = sys.argv[1:]
    if '--keywords' in args:
        keywords_index = args.index('--keywords') + 1
        raw_keywords = args[keywords_index:]  # Everything after --keywords
        processed_keywords, remaining_args = preprocess_keywords(raw_keywords)
        args = args[:keywords_index] + processed_keywords + remaining_args  # Combine processed and remaining args

    parser = argparse.ArgumentParser(description="A CLI tool for managing torrents.")
    parser.add_argument("-v", "--version", action="version", version="%(prog)s 1.0")
    parser.add_argument(
        "--force-update",
        action="store_true",
        help="Force delete, download, and reinsert data into the database even if it exists.",
    )
    parser.add_argument(
        "--keywords",
        type=str,
        nargs='+',
        help="Keywords to search in torrents (comma-separated, space within groups preserved).",
    )
    parser.add_argument("--set-debrid-api-key", type=str, help="API key for RealDebrid.")
    parser.add_argument("--download-range", type=str, help="Start and End index for downloading torrent into debrid")
    parser.add_argument("--download-to-debrid", type=str2bool, help="Flag to download torrents to RealDebrid.")
    parser.add_argument("--print-results", type=str2bool, help="Set to 'true' or 'false' to control printing results.")
    return parser.parse_args(args)

def force_update_database(url, filename, db_name):
    """Delete existing files, download the file, and insert data into the database."""
    print("Starting force update...")

    # Delete existing files
    delete_file_if_exists(filename)
    delete_file_if_exists(db_name)

    # Download the file
    downloader = TorrentCSVDownloader(url, filename)
    downloader.download()

    # Insert data into SQLite database
    database = TorrentDatabase(db_name)
    database.insert_data(filename)
    database.close()

    delete_file_if_exists(filename)

    print("Force update completed.")