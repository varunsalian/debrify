import os
import requests
from tqdm import tqdm

class TorrentCSVDownloader:
    def __init__(self, url, filename):
        self.url = url
        self.filename = filename

    def file_exists(self):
        """Check if the file already exists."""
        return os.path.exists(self.filename)

    def get_file_size(self):
        """Fetch the file size from the server using HEAD request."""
        try:
            response = requests.head(self.url)
            return int(response.headers.get("content-length", 0))
        except Exception as e:
            print(f"\033[1;31mFailed to fetch file size: {e}\033[0m")
            return 0

    def download(self):
        """Download the file with a progress bar."""
        if self.file_exists():
            print(f"\033[1;32m'{self.filename}' already exists. Skipping download.\033[0m")
            return

        try:
            file_size = self.get_file_size()
            print(f"\033[1;34mDownloading '{self.filename}'...\033[0m")

            with requests.get(self.url, stream=True) as response:
                response.raise_for_status()  # Check for HTTP errors
                with open(self.filename, "wb") as file, tqdm(
                    desc=self.filename,
                    total=file_size,
                    unit="B",
                    unit_scale=True,
                    unit_divisor=1024,
                    ncols=80,
                    colour="green",
                ) as progress_bar:
                    for chunk in response.iter_content(chunk_size=8192):
                        file.write(chunk)
                        progress_bar.update(len(chunk))

            print(f"\033[1;32m'{self.filename}' downloaded successfully.\033[0m")
        except Exception as e:
            print(f"\033[1;31mAn error occurred: {e}\033[0m")
