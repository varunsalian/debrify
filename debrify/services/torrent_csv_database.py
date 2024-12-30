import multiprocessing as mp
import sys
if sys.platform != "win32":
    mp.set_start_method('fork', force=True)
import duckdb

class TorrentDatabase:
    def __init__(self, db_name):
        self.db_name = db_name
        self.conn = duckdb.connect(self.db_name)
        self.create_table()
        print(f"\033[1;34mDatabase initialized with table 'torrents'.\033[0m")

    def create_table(self):
        create_table_query = """
        CREATE TABLE IF NOT EXISTS torrents (
            infohash TEXT PRIMARY KEY,
            name TEXT,
            size_bytes BIGINT,
            created_unix BIGINT,
            seeders INT,
            leechers INT,
            completed INT,
            scraped_date TEXT,
            published TEXT
        );
        """
        self.conn.execute(create_table_query)

    def insert_data(self, csv_file):
        try:
            print(f"\033[1;34mInserting data from '{csv_file}' into the database...\033[0m")
            # Use DuckDB's `read_csv_auto` to directly load the file
            self.conn.execute(f"""
            COPY torrents FROM '{csv_file}' (AUTO_DETECT TRUE, HEADER TRUE);
            """)
            print(f"\033[1;32mData successfully inserted into the database.\033[0m")
        except Exception as e:
            print(f"\033[1;31mAn error occurred while inserting data: {e}\033[0m")

    def close(self):
        self.conn.close()
        print(f"\033[1;34mDatabase connection closed.\033[0m")
