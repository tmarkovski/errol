#!/usr/bin/env bash
# Where the site's copies of the promo films live: in R2, under a hash of the
# source they're rendered from. CI renders them only when that hash is new, and
# every deploy fetches them into public/demos/ before the build.
#
#   films.sh key      print the hash of the films' source
#   films.sh bucket   create the bucket if it's missing; fails early on a token without R2 access
#   films.sh stored   succeed if the films for this source are in R2
#   films.sh store    upload the films in public/demos/ under the hash
#   films.sh fetch    download the films for this source into public/demos/
#
# wrangler needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID, or `wrangler login`.
set -euo pipefail
cd "$(dirname "$0")/../.."

BUCKET=errol-promo-films
FILES=(
  errol-promo-16x9.mp4 errol-promo-16x9-poster.webp
  errol-promo-9x16.mp4 errol-promo-9x16-poster.webp
)
# Everything a render reads. Git's blob hashes stand in for the contents, so the
# key is the same on any machine with the same commit (or staged changes).
SOURCES=(
  scripts/promo-film/promo.html scripts/promo-film/render.py scripts/promo-film/sound.py
  public/app-icons/chatgpt.png public/app-icons/claude.png
)

key() { git ls-files -s -- "${SOURCES[@]}" | git hash-object --stdin | cut -c1-16; }
wrangler() { npx --no-install wrangler "$@"; }

case "${1:-}" in
  key)
    key
    ;;
  bucket)
    wrangler r2 bucket info "$BUCKET" >/dev/null 2>&1 || wrangler r2 bucket create "$BUCKET"
    ;;
  stored)
    # The marker goes up last, so its presence means all the films made it.
    wrangler r2 object get "$BUCKET/$(key)/complete" --pipe --remote >/dev/null 2>&1
    ;;
  store)
    k=$(key)
    for f in "${FILES[@]}"; do
      type=video/mp4
      [[ $f == *.webp ]] && type=image/webp
      wrangler r2 object put "$BUCKET/$k/$f" --file "public/demos/$f" --content-type "$type" --remote
    done
    git rev-parse HEAD | wrangler r2 object put "$BUCKET/$k/complete" --pipe --remote
    echo "Stored the films for $k."
    ;;
  fetch)
    k=$(key)
    mkdir -p public/demos
    for f in "${FILES[@]}"; do
      wrangler r2 object get "$BUCKET/$k/$f" --file "public/demos/$f" --remote
    done
    echo "Fetched the films for $k."
    ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
