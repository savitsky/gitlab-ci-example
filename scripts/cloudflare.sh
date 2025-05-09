#!/bin/bash

# Get API-key from env
API_EMAIL=${API_EMAIL:-""}
API_KEY=${API_KEY:-""}
BASE_URL="https://api.cloudflare.com/client/v4"

# Check API_EMAIL and API_KEY are exists
if [ -z "$API_EMAIL" ] || [ -z "$API_KEY" ]; then
  echo "Error: API_EMAIL and API_KEY must be set as environment variables."
  exit 1
fi

# Help
function show_help() {
  echo "Usage: $0 [--create|--purge|--delete] <domain_name>"
  echo "  --create      Create a DNS record for the given domain name."
  echo "                [--type=A|CNAME] [--content=<IP_or_target>] [--proxied=true|false]"
  echo "                Default options for --create:"
  echo "                  --type='CNAME'"
  echo "                  --content='web.alphadao.net'"
  echo "                  --proxied=true"
  echo "  --purge       Purge cache for the given domain's zone."
  echo "  --delete      Delete the DNS record for the given domain name."
}

# Check if record already exists
function get_record_id() {
  local domain_name=$1
  local record_type=$2
  local zone_id=$3

  local dns_record=$(curl -s -X GET "$BASE_URL/zones/$zone_id/dns_records?type=$record_type&name=$domain_name" \
    -H "X-Auth-Email: $API_EMAIL" \
    -H "X-Auth-Key: $API_KEY" \
    -H "Content-Type: application/json")

  local record_id=$(echo "$dns_record" | jq -r '.result | if length > 0 then .[0].id else empty end')

  echo "$record_id"
}

# Check arguments
if [ "$#" -lt 2 ]; then
  show_help
  exit 1
fi

ACTION=$1
DOMAIN_NAME=$2
RECORD_TYPE="CNAME"               # Default value
RECORD_CONTENT="lb.example.com" # Default value
PROXIED=true                      # Default value

# Parse additional arguments
shift 2
while [[ $# -gt 0 ]]; do
  case $1 in
    --type=*)
      RECORD_TYPE="${1#*=}"
      ;;
    --content=*)
      RECORD_CONTENT="${1#*=}"
      ;;
    --proxied=*)
      PROXIED="${1#*=}"
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
  shift
done

# Get zone_id and zone name
ZONE_INFO=$(curl -s -X GET "$BASE_URL/zones?name=$(echo $DOMAIN_NAME | cut -d'.' -f2-3)" \
  -H "X-Auth-Email: $API_EMAIL" \
  -H "X-Auth-Key: $API_KEY" \
  -H "Content-Type: application/json")

ZONE_ID=$(echo "$ZONE_INFO" | jq -r '.result[0].id')
ZONE_NAME=$(echo "$ZONE_INFO" | jq -r '.result[0].name')

if [ -z "$ZONE_ID" ]; then
  echo "Error: Unable to find zone ID for domain $DOMAIN_NAME"
  exit 1
fi

echo "Zone: $ZONE_NAME (ID: $ZONE_ID)"

case "$ACTION" in
  --create)
    if [ -z "$RECORD_CONTENT" ]; then
      echo "Error: --content is required for creating a DNS record."
      exit 1
    fi

    EXISTING_RECORD_ID=$(get_record_id "$DOMAIN_NAME" "$RECORD_TYPE" "$ZONE_ID")

    if [ -n "$EXISTING_RECORD_ID" ]; then
      echo "Record already exists for $DOMAIN_NAME with ID: $EXISTING_RECORD_ID"
    else
      echo "Creating new DNS record for $DOMAIN_NAME..."
      RESPONSE=$(curl -s -X POST "$BASE_URL/zones/$ZONE_ID/dns_records" \
        -H "X-Auth-Email: $API_EMAIL" \
        -H "X-Auth-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        --data '{"type":"'$RECORD_TYPE'","name":"'$DOMAIN_NAME'","content":"'$RECORD_CONTENT'","ttl":3600,"proxied":'$PROXIED'}')

      SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
      if [ "$SUCCESS" == "true" ]; then
        echo "Record created successfully: $(echo "$RESPONSE" | jq -r '.result.id')"
      else
        echo "Failed to create record: $(echo "$RESPONSE" | jq -r '.errors[] | .message')"
      fi
    fi
    ;;

   --purge)
    # Clear cache for subdomain
    echo "Purging cache for domain $DOMAIN_NAME in zone $ZONE_NAME..."
    RESPONSE=$(curl -s -X POST "$BASE_URL/zones/$ZONE_ID/purge_cache" \
      -H "X-Auth-Email: $API_EMAIL" \
      -H "X-Auth-Key: $API_KEY" \
      -H "Content-Type: application/json" \
      --data '{"files":["https://'$DOMAIN_NAME'"]}')

    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    if [ "$SUCCESS" == "true" ]; then
      echo $RESPONSE | jq .
      echo "Cache purged successfully for domain $DOMAIN_NAME."
    else
      echo $RESPONSE | jq .
      echo "Failed to purge cache for domain $DOMAIN_NAME: $(echo "$RESPONSE" | jq -r '.errors[] | .message')"
    fi
    ;;

  --delete)
    # Delete subdomain
    RECORD_ID=$(get_record_id "$DOMAIN_NAME" "$RECORD_TYPE" "$ZONE_ID")

    if [ -n "$RECORD_ID" ]; then
      echo "Deleting DNS record for $DOMAIN_NAME..."
      RESPONSE=$(curl -s -X DELETE "$BASE_URL/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        -H "X-Auth-Email: $API_EMAIL" \
        -H "X-Auth-Key: $API_KEY" \
        -H "Content-Type: application/json")

      SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
      if [ "$SUCCESS" == "true" ]; then
        echo "Record deleted successfully for $DOMAIN_NAME."
      else
        echo "Failed to delete record for $DOMAIN_NAME: $(echo "$RESPONSE" | jq -r '.errors[] | .message')"
      fi
    else
      echo "No record found to delete for $DOMAIN_NAME."
    fi
    ;;

  *)
    echo "Unknown action: $ACTION"
    show_help
    exit 1
    ;;
esac
