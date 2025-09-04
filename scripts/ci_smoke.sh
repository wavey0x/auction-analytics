#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"

echo "Smoke testing API at $BASE_URL"

curl_json() {
  url="$1"
  echo "GET $url"
  http_code=$(curl -sS -o /tmp/resp.json -w "%{http_code}" --max-time 10 "$url") || { echo "Curl failed for $url"; exit 1; }
  cat /tmp/resp.json | head -c 200 >/dev/null || true
  if [[ "$http_code" != "200" ]]; then
    echo "Non-200 $http_code from $url" >&2
    exit 1
  fi
}

curl_json "$BASE_URL/health"
curl_json "$BASE_URL/status"
curl_json "$BASE_URL/system/stats"
curl_json "$BASE_URL/auctions"

# SSE endpoint basic check (just headers)
echo "HEAD $BASE_URL/events/stream"
code=$(curl -sS -I -o /tmp/hdrs.txt -w "%{http_code}" --max-time 5 "$BASE_URL/events/stream") || true
grep -qi "text/event-stream" /tmp/hdrs.txt || echo "Warning: SSE content-type not detected (this may be fine in CI)"
echo "HTTP $code for SSE"
exit 0

