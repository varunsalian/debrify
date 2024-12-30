import multiprocessing as mp
import sys
if sys.platform != "win32":
    mp.set_start_method('fork', force=True)
import duckdb

class TorrentCSVSearch:
    def __init__(self, db_name):
        """Initialize the database connection."""
        self.db_name = db_name
        self.conn = duckdb.connect(self.db_name)
        print(f"\033[1;34mConnected to database: '{self.db_name}'.\033[0m")

    def search_title(self, query, case_sensitive=False):
        """
        Search for a title in the torrents table where all query words must be present.

        Parameters:
            query (str): The search query (can be one or more words).
            case_sensitive (bool): If True, performs case-sensitive search.

        Returns:
            list: Matching records as dictionaries.
        """
        search_terms = query.split()
        results = []

        try:
            # Build the WHERE condition to ensure all terms are present
            conditions = []
            for term in search_terms:
                if case_sensitive:
                    conditions.append(f"name LIKE '%{term}%'")
                else:
                    conditions.append(f"LOWER(name) LIKE LOWER('%{term}%')")

            combined_condition = " AND ".join(conditions)

            # Execute the search query
            sql_query = f"SELECT * FROM torrents WHERE {combined_condition};"
            results = self.conn.execute(sql_query).fetchall()

            # Display the results
            if results:
                print(f"\033[1;32mFound {len(results)} matching records.\033[0m")
            else:
                print(f"\033[1;33mNo matching records found.\033[0m")

            return results
        except Exception as e:
            print(f"\033[1;31mAn error occurred during search: {e}\033[0m")
            return []

    def close(self):
        """Close the database connection."""
        self.conn.close()
        print(f"\033[1;34mDatabase connection closed.\033[0m")
