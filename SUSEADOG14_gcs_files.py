import os
from google.cloud import storage
from google.oauth2 import service_account

# Path to your service account key file
KEY_FILE = "/root/jsonfiles/ti-dba-prod-01.json"

# Source and destination details
SOURCE_BUCKET_NAME = "ti-dba-prod-sql-01"
SOURCE_PREFIX = "Backups/Current/MSSQL/SUSEADOG14"
DEST_BUCKET_NAME = "ti-sql-02"
DEST_PREFIX = "Backups/Current/SUSEADOG14"

# Authenticate using the service account key file
if not os.path.exists(KEY_FILE):
    raise FileNotFoundError(f"Service account key file not found: {KEY_FILE}")

credentials = service_account.Credentials.from_service_account_file(KEY_FILE)
storage_client = storage.Client(credentials=credentials, project=credentials.project_id)

source_bucket = storage_client.bucket(SOURCE_BUCKET_NAME)
dest_bucket = storage_client.bucket(DEST_BUCKET_NAME)

def copy_files():
    blobs = storage_client.list_blobs(source_bucket, prefix=SOURCE_PREFIX)

    for blob in blobs:
        dest_path = os.path.join(DEST_PREFIX, os.path.relpath(blob.name, SOURCE_PREFIX))
        dest_blob = dest_bucket.blob(dest_path)
        
        # Check if the file already exists in the destination bucket
        if dest_blob.exists():
            print(f"Skipping {blob.name}, already exists.")
        else:
            print(f"Copying {blob.name} to {dest_path}")

            # Copy the blob, retaining its metadata
            new_blob = source_bucket.copy_blob(blob, dest_bucket, dest_path)
            
            # Set the destination blob's properties to match the source blob
            new_blob.content_type = blob.content_type
            new_blob.cache_control = blob.cache_control
            new_blob.content_encoding = blob.content_encoding
            new_blob.content_language = blob.content_language
            new_blob.content_disposition = blob.content_disposition
            new_blob.metadata = blob.metadata
            new_blob.update()

            print(f"Copied {blob.name} to {new_blob.name}")

if __name__ == "__main__":
    copy_files()
