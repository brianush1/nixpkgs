#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl libxml2

set -o errexit -o nounset -o pipefail

BASE_URL="https://persistent.oaistatic.com/codex-app-prod"
SOURCE_NIX="$(dirname "${BASH_SOURCE[0]}")/source.nix"

convert_hash() {
  nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$1"
}

package_field() {
  local metadata="$1"
  local field="$2"
  awk -F ': ' -v field="$field" '$1 == field { print $2; exit }' <<< "$metadata"
}

appcast="$(curl --fail --silent --show-error "$BASE_URL/appcast.xml")"
darwin_version="$(xmllint --xpath '/rss/channel/item[1]/*[local-name()="shortVersionString"]/text()' - <<< "$appcast")"
darwin_url="$(xmllint --xpath 'string(/rss/channel/item[1]/enclosure/@url)' - <<< "$appcast")"
darwin_hash="$(nix-prefetch-url "$darwin_url" | xargs nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri)"

amd64_metadata="$(curl --fail --silent --show-error "$BASE_URL/linux/deb/dists/stable/main/binary-amd64/Packages")"
amd64_version="$(package_field "$amd64_metadata" Version)"
amd64_filename="$(package_field "$amd64_metadata" Filename)"
amd64_hash="$(convert_hash "$(package_field "$amd64_metadata" SHA256)")"

arm64_metadata="$(curl --fail --silent --show-error "$BASE_URL/linux/deb/dists/stable/main/binary-arm64/Packages")"
arm64_version="$(package_field "$arm64_metadata" Version)"
arm64_filename="$(package_field "$arm64_metadata" Filename)"
arm64_hash="$(convert_hash "$(package_field "$arm64_metadata" SHA256)")"

cat > "$SOURCE_NIX" << EOF
{
  aarch64-darwin = {
    version = "$darwin_version";
    url = "$darwin_url";
    hash = "$darwin_hash";
  };
  aarch64-linux = {
    version = "$arm64_version";
    name = "chatgpt_arm64.deb";
    url = "$BASE_URL/linux/deb/$arm64_filename";
    hash = "$arm64_hash";
  };
  x86_64-linux = {
    version = "$amd64_version";
    name = "chatgpt_amd64.deb";
    url = "$BASE_URL/linux/deb/$amd64_filename";
    hash = "$amd64_hash";
  };
}
EOF
