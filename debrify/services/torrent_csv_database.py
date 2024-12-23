import sqlite3
import csv
from tqdm import tqdm
from ..utils import common_utils

class TorrentDatabase:
    def __init__(self, db_name):
        self.db_name = db_name
        self.conn = sqlite3.connect(self.db_name)
        self.create_table()

    def create_table(self):
        """Create torrents table if it doesn't already exist."""
        create_table_query = """
        CREATE TABLE IF NOT EXISTS torrents (
            infohash TEXT PRIMARY KEY,
            name TEXT,
            size_bytes INTEGER,
            created_unix INTEGER,
            seeders INTEGER,
            leechers INTEGER,
            completed INTEGER,
            scraped_date TEXT,
            published TEXT
        );
        """
        self.conn.execute(create_table_query)
        self.conn.commit()
        print(f"\033[1;34mDatabase initialized with table 'torrents'.\033[0m")

    def insert_data(self, csv_file):
        """Insert data from CSV into the database with progress bar."""
        try:
            print(f"\033[1;34mInserting data from '{csv_file}' into the database...\033[0m")
            with open(csv_file, "r", encoding="utf-8") as file:
                # Change the delimiter to a comma (',')
                reader = csv.DictReader(file, delimiter=",")

                # Debug: Print detected fieldnames
                print(f"Detected CSV headers: {reader.fieldnames}")

                records = [
                    (
                        row["infohash"].strip(),
                        row["name"].strip(),
                        int(row["size_bytes"]),
                        int(row["created_unix"]),
                        int(row["seeders"]),
                        int(row["leechers"]),
                        int(row["completed"]),
                        row["scraped_date"].strip(),
                        row["published"].strip()
                    )
                    for row in reader
                ]

            insert_query = """
            INSERT OR IGNORE INTO torrents
            (infohash, name, size_bytes, created_unix, seeders, leechers, completed, scraped_date, published)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            with self.conn:
                for record in tqdm(records, desc="Inserting Records", unit="record", ncols=80, colour="cyan"):
                    self.conn.execute(insert_query, record)
            self.conn.commit()

            print(f"\033[1;32mData successfully inserted into the database.\033[0m")
        except Exception as e:
            print(f"\033[1;31mAn error occurred while inserting data: {e}\033[0m")


    def close(self):
        """Close the database connection."""
        self.conn.close()
        print(f"\033[1;34mDatabase connection closed.\033[0m")
