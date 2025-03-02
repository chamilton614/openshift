#!/bin/bash

# Configuration
SOURCE_REGISTRY="quay.io/source-org"  # Replace with your source Quay registry
DESTINATION_REGISTRY="quay.io/destination-org" # Replace with your destination Quay registry
SOURCE_LIST="source_images.txt" # Replace with your existing list file
DESTINATION_LIST="destination_images.txt"
DIFF_LIST="diff_images.txt"
SKOPEO_LOG="skopeo_copy.log"

# Function to get all images and tags from a Quay registry
get_quay_images() {
  local registry="$1"
  local output="$2"
  local page=1
  local page_size=100
  local all_images=""

  while true; do
    local response=$(curl -s "https://$registry/api/v1/repository?page=$page&page_size=$page_size")
    local repositories=$(echo "$response" | jq -r '.repositories[] | .name')

    if [[ -z "$repositories" ]]; then
      break
    fi

    for repo in $repositories; do
      local tags_response=$(curl -s "https://$registry/api/v1/repository/$repo/tag")
      local tags=$(echo "$tags_response" | jq -r '.tags[] | .name')

      if [[ -n "$tags" ]]; then
        for tag in $tags; do
          all_images+="$repo:$tag\n"
        done
      fi
    done

    page=$((page + 1))
  done

  echo "$all_images" > "$output"
}

# Get images and tags from source registry
echo "Fetching images from $SOURCE_REGISTRY..."
get_quay_images "$SOURCE_REGISTRY" "$SOURCE_LIST"

# Get images and tags from destination registry
echo "Fetching images from $DESTINATION_REGISTRY..."
get_quay_images "$DESTINATION_REGISTRY" "$DESTINATION_LIST"

# Compare new list with existing list
echo "Comparing lists..."
comm -13 "$SOURCE_LIST" "$DESTINATION_LIST" > "$DIFF_LIST"

# Process diff list and copy images using skopeo
echo "Copying images..."
if [[ -s "$DIFF_LIST" ]]; then
  while IFS= read -r image; do
    source_image="$SOURCE_REGISTRY/$image"
    destination_image="$DESTINATION_REGISTRY/$image"
    echo "Copying $source_image to $destination_image..."
    skopeo copy "docker://$source_image" "docker://$destination_image" >> "$SKOPEO_LOG" 2>&1
    if [[ $? -ne 0 ]]; then
      echo "Error copying $source_image. Check $SKOPEO_LOG for details."
    fi

  done < "$DIFF_LIST"
else
  echo "No new images to copy."
fi

echo "Done."