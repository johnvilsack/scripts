#!/bin/bash

# Script to find and delete duplicate large files (>10MB) in Google Drive

# Requirements:
# - jq installed
# - gum installed for interactive UI
# - token.json containing OAuth access token

# Check dependencies
for cmd in jq gum curl; do
  if ! command -v $cmd &>/dev/null; then
    echo "Error: $cmd is not installed. Please install it before running this script."
    exit 1
  fi
done

# Check for token.json and extract access token
if [[ ! -f token.json ]]; then
  echo "Error: token.json not found. Please provide OAuth token file."
  exit 1
fi

ACCESS_TOKEN=$(jq -r '.access_token' token.json)
if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "Error: access_token not found in token.json."
  exit 1
fi

echo "Retrieving list of files >10MB from Google Drive..."

# Function to fetch files with pagination
fetch_files() {
  local pageToken=$1
  local url="https://www.googleapis.com/drive/v3/files"
  local query="trashed = false and size > 10485760"
  local fields="nextPageToken, files(id, name, size, createdTime)"
  local params="pageSize=1000&fields=$fields&q=$(jq -sRr @uri <<<"$query")"
  if [[ -n "$pageToken" ]]; then
    params+="&pageToken=$pageToken"
  fi

  curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$url?$params"
}

# Retrieve all files >10MB
files=()
nextPageToken=""
while :; do
  resp=$(fetch_files "$nextPageToken")
  files+=( "$(jq -c '.files[]' <<<"$resp")" )
  nextPageToken=$(jq -r '.nextPageToken // empty' <<<"$resp")
  [[ -z "$nextPageToken" ]] && break
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files >10MB found or error retrieving files."
  exit 0
fi

# Group files by name, size, and createdTime
declare -A groups

for file_json in "${files[@]}"; do
  name=$(jq -r '.name' <<<"$file_json")
  size=$(jq -r '.size' <<<"$file_json")
  created=$(jq -r '.createdTime' <<<"$file_json")
  key="${name}|${size}|${created}"
  groups["$key"]+="$file_json"$'\n'
done

echo "Identifying potential duplicate groups..."

declare -A dup_groups

for key in "${!groups[@]}"; do
  count=$(echo -n "${groups[$key]}" | grep -c '^')
  if (( count > 1 )); then
    dup_groups["$key"]="${groups[$key]}"
  fi
done

if [[ ${#dup_groups[@]} -eq 0 ]]; then
  echo "No duplicate groups found based on name, size, and creation date."
  exit 0
fi

echo "Found ${#dup_groups[@]} groups with potential duplicates."

# For each group, allow user to select duplicates for deletion
for key in "${!dup_groups[@]}"; do
  echo
  echo "Processing group with name|size|createdTime: $key"
  files="${dup_groups[$key]}"
  declare -A file_id_to_name

  declare -a gum_choices

  while IFS= read -r file_json; do
    id=$(jq -r '.id' <<<"$file_json")
    name=$(jq -r '.name' <<<"$file_json")
    file_id_to_name["$id"]="$name"
    gum_choices+=("$id" "$name")
  done < <(echo -n "$files")

  echo "Select files to delete (keep at least one):"
  to_delete=$(gum choose --no-limit --header "Select files to delete for group $key" "${gum_choices[@]}")

  if [[ -z "$to_delete" ]]; then
    echo "No files selected for deletion."
  else
    echo "You selected to delete:"
    echo "$to_delete" | while IFS= read -r del_id; do
      echo "- ${file_id_to_name[$del_id]}"
    done

    if gum confirm "Are you sure you want to delete the selected files from Google Drive?"; then
      echo "$to_delete" | while IFS= read -r del_id; do
        echo "Deleting ${file_id_to_name[$del_id]} (ID: $del_id)..."
        # Delete file using Google Drive API
        curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" "https://www.googleapis.com/drive/v3/files/$del_id"
      done
    else
      echo "Deletion cancelled."
    fi
  fi
done

echo
echo "Duplicate processing complete."
