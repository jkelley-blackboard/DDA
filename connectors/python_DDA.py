import psycopg2
from psycopg2 import OperationalError, ProgrammingError
from psycopg2.errors import ReadOnlySqlTransaction
from typing import Optional, List, Tuple, Dict
from configparser import ConfigParser
import csv
import os

# Define suffixes for the main databases used by DDA
DB_SUFFIXES = {
    'main': '',          # BBxxxxxxxxxxxx (Primary production database - Core app tables)
    'admin': '_admin',   # BBxxxxxxxxxxxx_admin (System coordination/metadata)
    'stats': '_stats',   # BBxxxxxxxxxxxx_stats (Reporting and analytics)
    'cms_doc': '_cms_doc', # BBxxxxxxxxxxxx_cms_doc (Content Collection document store)
    'cms': '_cms',       # BBxxxxxxxxxxxx_cms (Content Collection admin database/metadata)
}

# --- Configuration Loader ---
def load_config(filename: str = 'database_config.ini', section: str = 'postgresql') -> Dict[str, str]:
    """
    Reads the PostgreSQL database configuration from an external INI file.

    It expects a base ID (e.g., 'BB1234567890') which is used to construct
    the full database name (e.g., BB1234567890_stats) during connection.

    Args:
        filename (str): The name of the configuration file.
        section (str): The section name within the file to read (e.g., 'postgresql').

    Returns:
        Dict[str, str]: A dictionary containing the configuration parameters including the base ID.

    Raises:
        Exception: If the configuration file, the specified section, or a required key is not found.
    """
    parser = ConfigParser()
    
    if not parser.read(filename):
        raise FileNotFoundError(f"Configuration file '{filename}' not found or could not be read.")

    config = {}
    if parser.has_section(section):
        params = parser.items(section)
        for param in params:
            config[param[0]] = param[1]
    else:
        raise Exception(f'Section {section} not found in the {filename} file.')
    
    # Ensure all required keys are present
    required_keys = ['host', 'bb_base_id', 'user', 'password', 'port']
    missing_keys = [k for k in required_keys if k not in config]
    if missing_keys:
        raise ValueError(f"Missing required configuration keys in '{section}' section: {', '.join(missing_keys)}")

    return config

def _connect_and_query_internal(config: Dict[str, str], db_type: str, query: str, params: Optional[Tuple] = None) -> Optional[Tuple[List[str], List[Tuple]]]:
    """
    Internal function to establish a read-only connection, execute a SELECT query, 
    and return the column headers and resulting rows.

    Args:
        config (Dict[str, str]): Loaded configuration.
        db_type (str): The type of database to connect to ('main', 'admin', 'stats', 'cms_doc', or 'cms').
        query (str): The SQL query string to execute. MUST be a SELECT statement for DDA.
        params (Optional[Tuple]): A tuple of values for query substitution.

    Returns:
        Optional[Tuple[List[str], List[Tuple]]]: A tuple containing (column_headers, fetched_rows).
    """
    conn = None
    results = None
    headers = None
    
    # 1. Dynamically construct the full database name
    base_id = config.get('bb_base_id')
    suffix = DB_SUFFIXES.get(db_type.lower())
    
    if suffix is None:
        print(f"Error: Invalid database type '{db_type}'. Must be one of: {', '.join(DB_SUFFIXES.keys())}")
        return None
        
    full_db_name = f"{base_id}{suffix}"

    print(f"\nAttempting to connect to database '{db_type}' ({full_db_name}) at {config.get('host')}")

    try:
        # 2. Establish the connection in READ-ONLY mode
        conn = psycopg2.connect(
            host=config.get("host"),
            database=full_db_name, # Use the dynamically constructed name
            user=config.get("user"),
            password=config.get("password"),
            port=config.get("port"),
            readonly=True
        )
        
        print("Connection successful (READ-ONLY mode). Executing query...")

        # 3. Execute the SQL query
        with conn.cursor() as cursor:
            cursor.execute(query, params)

            if cursor.description:
                # Get column headers
                headers = [desc[0] for desc in cursor.description]
                results = cursor.fetchall()
                print(f"SELECT query executed successfully. Fetched {len(results)} rows.")
            else:
                print("Warning: Non-SELECT query executed, but no commit was performed as this is a read replica.")

    except ReadOnlySqlTransaction as e:
        print(f"!!! CRITICAL ERROR on {full_db_name}: Attempted a Write Operation. Transaction rejected.")
        print(f"Error details: {e}")
    except OperationalError as e:
        print(f"A PostgreSQL Operational Error occurred (Database: {full_db_name}): {e}")
        print("Check connection details (host, port, network access) or database existence.")
    except ProgrammingError as e:
        print(f"A PostgreSQL Programming Error occurred (Database: {full_db_name}): {e}")
        print("Please check your SQL syntax or database permissions.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    
    finally:
        if conn:
            print("Connection context exited.")
    
    return (headers, results) if headers else None


# --- CSV Export Function ---
def _export_to_csv_internal(headers: List[str], data: List[Tuple], filepath: str) -> None:
    """
    Internal function to write the query results and headers to a CSV file.
    
    Args:
        headers (List[str]): List of column names.
        data (List[Tuple]): List of tuples representing the rows.
        filepath (str): The destination path for the CSV file.
    """
    try:
        # Use Python's built-in csv writer for robust comma and quote handling
        with open(filepath, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.writer(csvfile, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)
            
            # Write headers
            if headers:
                writer.writerow(headers)
            
            # Write data rows
            writer.writerows(data)
            
        print(f"\nSuccessfully exported {len(data)} rows to CSV: {os.path.abspath(filepath)}")

    except IOError as e:
        print(f"\nError writing to CSV file {filepath}: {e}")


# --- Public Utility Function ---
def run_dda_query_and_export(db_type: str, query: str, filepath: str, params: Optional[Tuple] = None) -> bool:
    """
    The main utility function to execute a DDA query and export results to a CSV file.

    This function handles configuration loading, database connection, query execution,
    and CSV file creation.

    Args:
        db_type (str): The target database ('main', 'admin', 'stats', 'cms_doc', or 'cms').
        query (str): The SQL SELECT query to execute.
        filepath (str): The full path to the output CSV file.
        params (Optional[Tuple]): Parameters for query substitution.

    Returns:
        bool: True if the operation was successful, False otherwise.
    """
    try:
        # 1. Load configuration
        config = load_config()

        # 2. Execute query
        query_result = _connect_and_query_internal(
            config=config, 
            db_type=db_type, 
            query=query, 
            params=params
        )
        
        # 3. Process and export results
        if query_result and query_result[0] and query_result[1]:
            headers, data = query_result
            _export_to_csv_internal(headers, data, filepath)
            return True
        else:
            print("\nQuery failed, or no data was returned; skipping CSV export.")
            return False

    except FileNotFoundError as e:
        print(f"\nConfiguration Error: {e}")
        print("Ensure 'database_config.ini' is present and correct.")
        return False
    except ValueError as e:
        print(f"\nConfiguration Error: {e}")
        return False
    except Exception as e:
        print(f"\nGeneral Error during DDA execution: {e}")
        return False

# --- Example Usage ---
if __name__ == "__main__":
    # NOTE: Before running, you must install the library:
    # pip install psycopg2-binary
    
    # Check if credentials were updated before attempting to run the utility
    try:
        POSTGRES_CONFIG = load_config()
        base_id_placeholder = "BBxxxxxxxxxxxx_BASE_ID"
        if POSTGRES_CONFIG.get('user') == "YOUR_PG_USER" or POSTGRES_CONFIG.get('bb_base_id') == base_id_placeholder:
            print("\n*** ERROR: Please update the 'database_config.ini' file with your actual PostgreSQL credentials and base ID. ***")
        else:
            # --- 1. Define the parameters for the MAIN database report ---
            DDA_QUERY_MAIN = "SELECT u.user_id, u.first_name, u.last_name, u.email FROM users u WHERE u.account_status = %s LIMIT 5;"
            QUERY_PARAMS_MAIN = ('ENABLED',)
            CSV_FILEPATH_MAIN = "dda_main_enabled_users_report.csv"
            
            print("\n*** DEMO: Calling run_dda_query_and_export for MAIN DB ***")
            run_dda_query_and_export(
                db_type='main', 
                query=DDA_QUERY_MAIN, 
                filepath=CSV_FILEPATH_MAIN,
                params=QUERY_PARAMS_MAIN
            )

            # --- 2. Define the parameters for the STATS database report ---
            DDA_QUERY_STATS = "SELECT activity_pk1, timestamp FROM activity_accumulator LIMIT 5;"
            CSV_FILEPATH_STATS = "dda_stats_activity_report.csv"
            
            print("\n*** DEMO: Calling run_dda_query_and_export for STATS DB ***")
            run_dda_query_and_export(
                db_type='stats', 
                query=DDA_QUERY_STATS, 
                filepath=CSV_FILEPATH_STATS
            )

            # --- 3. Test DML (Write operation) - Expected to FAIL ---
            DML_FAIL_QUERY = "CREATE TABLE dummy_read_replica_test (id INT);"
            print("\n*** DEMO: Testing DML Query (Expected to FAIL due to Read-Only flag) ***")
            run_dda_query_and_export(
                db_type='main',
                query=DML_FAIL_QUERY,
                filepath="dml_test_output.csv" # This file won't be created
            )


    except Exception as e:
        print(f"\nStartup Error: {e}")
