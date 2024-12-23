import sqlite3

class TorrentCSVSearch:
    def __init__(self, db_name):
        """Initialize the database connection."""
        self.db_name = db_name
        self.conn = sqlite3.connect(self.db_name)
        print(f"\033[1;34mConnected to database: '{self.db_name}'.\033[0m")

    def search_title(self, query, case_sensitive=False):
        """
        Search for a title in the torrents table with Google-like flexibility.

        Parameters:
            query (str): The search query (can be one or more words).
            case_sensitive (bool): If True, performs case-sensitive search.

        Returns:
            list: Matching records as tuples.
        """
        cursor = self.conn.cursor()

        # Split the query into individual words (based on spaces)
        search_terms = query.split()

        # Prepare the LIKE conditions for each search term
        like_conditions = [f"%{term}%" for term in search_terms]
        sql_query = "SELECT * FROM torrents WHERE "

        # Create a list of conditions for the SQL query using the search terms
        sql_query += " AND ".join([f"LOWER(name) LIKE LOWER(?)" for _ in search_terms])

        try:
            # Execute the query
            # print(f"\033[1;34mExecuting search for terms: {search_terms}\033[0m")
            if case_sensitive:
                cursor.execute(sql_query, tuple(search_terms))  # Use exact case search
            else:
                cursor.execute(sql_query, tuple(like_conditions))  # Default case-insensitive search
            results = cursor.fetchall()

            # Display the results
            if results:
                print(f"\033[1;32mFound {len(results)} matching records.\033[0m")
            else:
                print(f"\033[1;33mNo matching records found.\033[0m")
            return results
        except Exception as e:
            print(f"\033[1;31mAn error occurred during search: {e}\033[0m")
            return []
        finally:
            cursor.close()

    def close(self):
        """Close the database connection."""
        self.conn.close()
        print(f"\033[1;34mDatabase connection closed.\033[0m")
