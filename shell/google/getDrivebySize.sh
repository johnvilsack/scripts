#!/bin/bash

# Requirements: gum, jq, curl, Python, Google OAuth client ID + secret in credentials.json

CREDENTIALS_JSON="credentials.json"
TOKEN_JSON="token.json"
SCOPES="https://www.googleapis.com/auth/drive"

# Function to refresh access token using refresh token
refresh_access_token() {
  REFRESH_TOKEN=$(jq -r .refresh_token $TOKEN_JSON)
  if [ "$REFRESH_TOKEN" = "null" ] || [ -z "$REFRESH_TOKEN" ]; then
    return 1
  fi
  RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d client_id=$(jq -r '.installed.client_id' $CREDENTIALS_JSON) \
    -d client_secret=$(jq -r '.installed.client_secret' $CREDENTIALS_JSON) \
    -d refresh_token="$REFRESH_TOKEN" \
    -d grant_type=refresh_token)
  ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r .access_token)
  if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    return 1
  fi
  # Update token.json with new access token, keep refresh token
  jq --arg at "$ACCESS_TOKEN" '.access_token=$at' $TOKEN_JSON > tmp_token.json && mv tmp_token.json $TOKEN_JSON
  return 0
}

if [ -f "$TOKEN_JSON" ]; then
  echo "Found existing token file. Attempting to refresh access token..."
  if ! refresh_access_token; then
    echo "Failed to refresh access token. Need to re-authorize."
    rm -f $TOKEN_JSON
  else
    echo "Access token refreshed successfully."
  fi
fi

if [ ! -f "$TOKEN_JSON" ]; then
  # Step 1: Generate auth URL and get authorization code
  echo "Getting authorization code..."
  AUTH_URL=$(python3 -c "
import json, urllib.parse
creds = json.load(open('$CREDENTIALS_JSON'))
p = {
  'client_id': creds['installed']['client_id'],
  'redirect_uri': creds['installed']['redirect_uris'][0],
  'response_type': 'code',
  'scope': '$SCOPES',
  'access_type': 'offline',
  'prompt': 'consent'
}
print('https://accounts.google.com/o/oauth2/v2/auth?' + urllib.parse.urlencode(p))")

  echo "Open the following URL in your browser and paste the code below:"
  echo "$AUTH_URL"
  read -p "Enter authorization code: " AUTH_CODE

  # Step 2: Exchange code for tokens
  echo "Getting tokens..."
  RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d code="$AUTH_CODE" \
    -d client_id=$(jq -r '.installed.client_id' $CREDENTIALS_JSON) \
    -d client_secret=$(jq -r '.installed.client_secret' $CREDENTIALS_JSON) \
    -d redirect_uri=$(jq -r '.installed.redirect_uris[0]' $CREDENTIALS_JSON) \
    -d grant_type=authorization_code)

  echo "$RESPONSE" > $TOKEN_JSON
  ACCESS_TOKEN=$(jq -r .access_token $TOKEN_JSON)
else
  ACCESS_TOKEN=$(jq -r .access_token $TOKEN_JSON)
fi

# Step 3: Get file list from Drive (including owners) with pagination
echo "Fetching file list..."
PAGE_TOKEN=""
ALL_FILES=()
while : ; do
  if [ -z "$PAGE_TOKEN" ]; then
    RESPONSE=$(curl -s -X GET \
      "https://www.googleapis.com/drive/v3/files?pageSize=1000&fields=nextPageToken,files(id,name,size,mimeType,modifiedTime,owners)" \
      -H "Authorization: Bearer $ACCESS_TOKEN")
  else
    RESPONSE=$(curl -s -X GET \
      "https://www.googleapis.com/drive/v3/files?pageSize=1000&fields=nextPageToken,files(id,name,size,mimeType,modifiedTime,owners)&pageToken=$PAGE_TOKEN" \
      -H "Authorization: Bearer $ACCESS_TOKEN")
  fi
  FILES_PAGE=$(echo "$RESPONSE" | jq '.files')
  ALL_FILES+=("$FILES_PAGE")
  PAGE_TOKEN=$(echo "$RESPONSE" | jq -r '.nextPageToken // empty')
  if [ -z "$PAGE_TOKEN" ]; then
    break
  fi
done

# Combine all pages into one JSON array
jq -s 'add' <(printf '%s\n' "${ALL_FILES[@]}") > files.json

# Step 4: Sort files by size and format for display, filtering only files owned by user
jq -r '.[] | select(.size != null) | select(.owners[0].me == true) | "\(.size)\t\(.name)\t\(.mimeType)\t\(.modifiedTime)\t\(.id)"' files.json | sort -nr > sorted_files.txt

# Step 5: Interactive file selection with Gum, showing name, mime type, size in KB or MB and modified date
printf "%-50s %-30s %-10s %-20s\n" "Name" "Type" "Size" "Modified Time"
FILE_DISPLAY=$(awk -F'\t' '{
  name = substr($2,1,50);
  size=$1;
  if (size < 1048576) {
    size_display = int(size/1024) " KB";
  } else {
    size_display = sprintf("%.2f MB", size/1048576);
  }
  printf "%-50s %-30s %-10s %-20s\t%s\n", name, $3, size_display, $4, $5
}' sorted_files.txt)
FILE_NAMES=$(echo "$FILE_DISPLAY" | cut -f1 | gum choose --no-limit --header="Select files to delete (Name, Type, Size, Modified Time):")

# Step 6: Delete selected files
for NAME in $FILE_NAMES; do
  FILE_ID=$(grep -F "$NAME" sorted_files.txt | cut -f5)
  echo "Deleting: $NAME"
  curl -s -X DELETE "https://www.googleapis.com/drive/v3/files/$FILE_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN"
done