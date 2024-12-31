import os
from debrify.clients import RealDebridClient
from debrify.services import TorrentCSVSearch
from debrify.utils import common_utils
from tqdm import tqdm
import yaml
from debrify.utils.common_utils import load_configs, display_results, parse_arguments, force_update_database, \
    get_absoulute_path, parse_download_range

def search_and_process_results(config):
    """Search for results and process them based on configuration."""
    keywords = config.get('keywords', [])
    if not keywords:
        print("Error: 'keywords' not found (either use --keyword flag and provide space separated keywords or use the config file to provide keywords)")
        return

    download_range = config.get('download_range', "0-2000000")
    download_start_from, download_end_at = parse_download_range(download_range)
    download_to_debrid = config.get('download_to_debrid', False)
    print_results = config.get('print_results', False)


    db_path = common_utils.get_absoulute_path(config.get('torrent_csv_destination_db_path', "data/torrents.db"))
    torrent_csv_search = TorrentCSVSearch(db_path)
    api_key = config.get('debrid_api_key', 'default_api_key')
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

def main():
    args = parse_arguments()

    if args.set_debrid_api_key:
        # Update the debrid API key in the configuration file
        config_path = get_absoulute_path('config/config.yaml')
        try:
            with open(config_path, 'r') as file:
                config = yaml.safe_load(file) or {}
        except FileNotFoundError:
            config = {}

        config['debrid_api_key'] = args.set_debrid_api_key

        with open(config_path, 'w') as file:
            yaml.safe_dump(config, file)

        print(f"Updated debrid_api_key in {config_path}.")
        return



    config = load_configs(args)

    url = config.get('torrent_csv_url', None)
    filename = common_utils.get_absoulute_path(config.get('torrent_csv_destination_file_path', None))
    db_name = common_utils.get_absoulute_path(config.get('torrent_csv_destination_db_path', None))

    if args.force_update:
        # If force_update is set, execute this first
        print("Force update triggered. Updating database...")
        force_update_database(url, filename, db_name)
        return

    # Continue only if force_update is not set
    if not database_exists(db_name):
        print("Database does not exist. Creating a new one.")
        force_update_database(url, filename, db_name)
    else:
        print("Database exists. Skipping download and reinsert. Use --force-update to overwrite with the latest version of the file.")

    search_and_process_results(config)


if __name__ == "__main__":
    main()
