import duckdb

class TorrentCSVSearch:
    def __init__(self, db_name):
        """Initialize the database connection."""
        self.db_name = db_name
        self.conn = duckdb.connect(self.db_name)
        print(f"\033[1;34mConnected to database: '{self.db_name}'.\033[0m")

    def search_title(self, query, case_sensitive=False):
        """
        Search for a title in the torrents table with Google-like flexibility.

        Parameters:
            query (str): The search query (can be one or more words).
            case_sensitive (bool): If True, performs case-sensitive search.

        Returns:
            list: Matching records as dictionaries.
        """
        search_terms = query.split()
        results = []

        try:
            for term in search_terms:
                if case_sensitive:
                    condition = f"name LIKE '%{term}%'"
                else:
                    condition = f"LOWER(name) LIKE LOWER('%{term}%')"

                # Execute the search query
                query = f"SELECT * FROM torrents WHERE {condition};"
                matches = self.conn.execute(query).fetchall()
                results.extend(matches)

            # Remove duplicates from results based on the 'infohash' column
            unique_results = {record[0]: record for record in results}.values()

            # Display the results
            if unique_results:
                print(f"\033[1;32mFound {len(unique_results)} matching records.\033[0m")
            else:
                print(f"\033[1;33mNo matching records found.\033[0m")

            return list(unique_results)
        except Exception as e:
            print(f"\033[1;31mAn error occurred during search: {e}\033[0m")
            return []

    def close(self):
        """Close the database connection."""
        self.conn.close()
        print(f"\033[1;34mDatabase connection closed.\033[0m")
