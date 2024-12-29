import os
from rdapi import RD
from debrify.utils import common_utils

# Set environment variables (ensure these are not committed to a public repo)
os.environ["SLEEP"] = "2000"
os.environ["LONG_SLEEP"] = "30000"


class RealDebridClient:
    def __init__(self, api_key, config_path="config.yaml"):
        """
        Initializes the Real-Debrid client with the provided API key and loads the configuration.

        Parameters:
            api_key (str): Your Real-Debrid API key.
            config_path (str): Path to the YAML configuration file.
        """
        self.api_key = api_key
        self.base_url = "https://api.real-debrid.com/rest/1.0"
        self.rd = RD()  # instantiate RD here
        self.config = common_utils.load_config()

    def add_magnet(self, magnet_link):
        """
        Adds a magnet link to Real-Debrid and processes the torrent based on the configuration.

        Parameters:
            magnet_link (str): The magnet link to add.
        """
        download_type = self.config.get("download_type", "highest_size")  # Default to "highest_size"
        response = self._add_magnet_link(magnet_link)
        torrent_id = response.get('id')

        if torrent_id:
            info_response = self._get_torrent_info(torrent_id)
            if download_type == "highest_size":
                largest_file = self._get_largest_file(info_response)
                if largest_file:
                    self._select_largest_file(torrent_id, largest_file)
                # else:
                #     print("No files found in the torrent.")
            elif download_type == "all":
                self._select_all_files(torrent_id)

            # Check if torrent links are available
            info_response = self._get_torrent_info(torrent_id)
            # print(info_response)
            if not info_response.get('links'):
                self._delete_torrent(torrent_id)
            # else:
            #     print(f"Downloadable Links: {info_response.get('links')}")
        # else:
        #     print("Error: Magnet link could not be added.")

    def _add_magnet_link(self, magnet_link):
        """
        Adds a magnet link to Real-Debrid and returns the response.

        Parameters:
            magnet_link (str): The magnet link to add.

        Returns:
            dict: The response containing the torrent ID.
        """
        response = self.rd.torrents.add_magnet(magnet_link).json()
        return response

    def _get_torrent_info(self, torrent_id):
        """
        Fetches torrent information for the given torrent ID.

        Parameters:
            torrent_id (str): The ID of the torrent to fetch info for.

        Returns:
            dict: The torrent info.
        """
        info_response = self.rd.torrents.info(torrent_id).json()
        return info_response

    def _get_largest_file(self, info_response):
        """
        Finds the file with the largest size from the torrent info.

        Parameters:
            info_response (dict): The response containing torrent files info.

        Returns:
            dict: The file with the largest size.
        """
        largest_file = max(info_response.get('files', []), key=lambda x: x['bytes'], default=None)
        return largest_file

    def _select_largest_file(self, torrent_id, largest_file):
        """
        Selects the largest file for download based on the file ID.

        Parameters:
            torrent_id (str): The ID of the torrent.
            largest_file (dict): The file to select based on the ID.
        """
        file_id = largest_file.get('id')
        self.rd.torrents.select_files(torrent_id, file_id)

    def _select_all_files(self, torrent_id):
        """
        Selects all files for download in the torrent.

        Parameters:
            torrent_id (str): The ID of the torrent.
        """
        self.rd.torrents.select_files(torrent_id, "all")

    def _delete_torrent(self, torrent_id):
        """
        Deletes a torrent based on the given torrent ID.

        Parameters:
            torrent_id (str): The ID of the torrent to delete.
        """
        self.rd.torrents.delete(torrent_id)
        # print("Deleting torrent")
