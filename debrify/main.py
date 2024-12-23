import argparse
import os
from .clients import RealDebridClient
from .services import TorrentDatabase, TorrentCSVSearch, TorrentCSVDownloader
from .utils import common_utils
from rich.console import Console
from rich.table import Table
from tqdm import tqdm


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


def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="A CLI tool for managing torrents.")
    parser.add_argument("-v", "--version", action="version", version="%(prog)s 1.0")
    parser.add_argument(
        "--force-update",
        action="store_true",
        help="Force delete, download, and reinsert data into the database even if it exists.",
    )
    parser.add_argument("--keywords", type=str, nargs='+', help="Keywords to search in torrents (space-separated).")
    parser.add_argument("--real-debrid-api-key", type=str, help="API key for RealDebrid.")
    parser.add_argument("--download-start-from", type=int, help="Start index for downloading torrents.")
    parser.add_argument("--download-end-at", type=int, help="End index for downloading torrents.")
    parser.add_argument("--download-to-debrid", action="store_true", help="Flag to download torrents to RealDebrid.")
    parser.add_argument("--print-results", type=str2bool, help="Set to 'true' or 'false' to control printing results.")
    return parser.parse_args()


def load_config(args):
    """Load the configuration and override with command-line arguments."""
    config = common_utils.load_config()

    if args.keywords:
        config['keywords'] = args.keywords
    if args.real_debrid_api_key:
        config['real_debrid_api_key'] = args.real_debrid_api_key
    if args.download_start_from is not None:
        config['download_start_from'] = args.download_start_from
    if args.download_end_at is not None:
        config['download_end_at'] = args.download_end_at
    if args.download_to_debrid:
        config['download_to_debrid'] = args.download_to_debrid
    if args.print_results is not None:
        config['print_results'] = args.print_results
    return config


def search_and_process_results(config):
    """Search for results and process them based on configuration."""
    keywords = config.get('keywords', [])
    if not keywords:
        print("Error: 'keywords' not found in the configuration file.")
        return

    download_start_from = config.get('download_start_from', 0)
    download_end_at = config.get('download_end_at', 1000000)
    download_to_debrid = config.get('download_to_debrid', False)
    print_results = config.get('print_results', False)


    db_path = common_utils.get_absoulute_path(config.get('torrent_csv_destination_db_path', "data/torrents.db"))
    torrent_csv_search = TorrentCSVSearch(db_path)
    api_key = config.get('real_debrid_api_key', 'default_api_key')
    os.environ["RD_APITOKEN"] = api_key
    debrid_client = RealDebridClient(api_key)

    for keyword in keywords:
        print(f"Processing keyword: {keyword}")
        results_csv = torrent_csv_search.search_title(keyword)
        total_results = len(results_csv)

        if print_results:
            display_results(results_csv, keyword)

        if download_end_at > total_results:
            download_end_at = total_results

        if download_start_from >= total_results:
            print(f"No results available to download from index {download_start_from} for keyword '{keyword}'.")
            continue

        process_torrents(results_csv, download_start_from, download_end_at, download_to_debrid, debrid_client)


def display_results(results_csv, keyword):
    """Display search results in a table."""
    console = Console()
    table = Table(title=f"Results for '{keyword}'")
    table.add_column("No.", style="cyan", justify="right")
    table.add_column("Data", style="magenta", justify="left")

    for index, data in enumerate(results_csv, start=1):
        table.add_row(f"{index:04}", data[1])

    console.print(table)


def process_torrents(results_csv, start, end, download_to_debrid, debrid_client):
    """Process torrents within the specified range."""
    print(f"Processing results from index {start} to {end - 1}...")

    for torrent in tqdm(results_csv[start:end], desc="Processing Torrents", unit="torrent"):
        magnet_link = f"magnet:?xt=urn:btih:{torrent[0]}"

        if download_to_debrid:
            debrid_client.add_magnet(magnet_link)

    print("Processing complete.")

def database_exists(db_path):
    """Check if the database file exists."""
    return os.path.exists(db_path)

def force_update_database(url, filename, db_name):
    """Delete existing files, download the file, and insert data into the database."""
    print("Starting force update...")

    # Delete existing files
    common_utils.delete_file_if_exists(filename)
    common_utils.delete_file_if_exists(db_name)

    # Download the file
    downloader = TorrentCSVDownloader(url, filename)
    downloader.download()

    # Insert data into SQLite database
    database = TorrentDatabase(db_name)
    database.insert_data(filename)
    database.close()

    print("Force update completed.")

def main():
    args = parse_arguments()
    config = load_config(args)

    url = config.get('torrent_csv_url', None)
    filename = common_utils.get_absoulute_path(config.get('torrent_csv_destination_file_path', None))
    db_name = common_utils.get_absoulute_path(config.get('torrent_csv_destination_db_path', None))

    if not database_exists(db_name) or args.force_update:
        if database_exists(db_name):
            print("Database exists. Force updating as per the argument.")
        else:
            print("Database does not exist. Creating a new one.")
        force_update_database(url, filename, db_name)
    else:
        print("Database exists. Skipping download and reinsert. Use --force-update to overwrite with the latest version of the file.")

    search_and_process_results(config)


if __name__ == "__main__":
    main()
