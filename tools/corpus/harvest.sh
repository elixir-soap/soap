#!/usr/bin/env bash
# Downloads the full WSDL harvest for the nightly conformance layer.
# Usage: tools/corpus/harvest.sh CORPUS_DIR
set -euo pipefail

out=${1:?usage: harvest.sh CORPUS_DIR}
here=$(cd "$(dirname "$0")" && pwd)
repos=(
  vpulim/node-soap mvantellingen/python-zeep savonrb/wasabi savonrb/savon php/php-src
  hooklift/gowsdl fiorix/wsdl2go bet365/soap onvif/specs apache/cxf apache/axis-axis2-java-core
  phpro/soap-client wsdl2phpgenerator/wsdl2phpgenerator php-soap/wsdl reficio/soap-ws dotnet/wcf
)

mkdir -p "$out/oss" "$out/live"

for repo in "${repos[@]}"; do
  dir="$out/oss/${repo//\//__}"
  [ -d "$dir" ] && continue
  git clone -q --depth 1 --filter=blob:none --no-checkout "https://github.com/$repo.git" "$dir"
  git -C "$dir" sparse-checkout set --no-cone '*.wsdl' '*.WSDL' '*.wsdl.xml' '*.xsd'
  git -C "$dir" checkout -q
done

python3 -c 'import json,sys; [print(w["url"]) for w in json.load(open(sys.argv[1]))["wsdls"]]' \
  "$here/../../test/corpus/live_services.json" > "$out/live_urls.txt"

n=0
while read -r url; do
  n=$((n + 1))
  dir="$out/live/$(printf '%03d' "$n")"
  mkdir -p "$dir"
  echo "$url" > "$dir/url"
  curl -sSL --max-time 30 --max-filesize 40000000 -A 'soap-corpus-harvest' -o "$dir/body" "$url" || rm -f "$dir/body"
done < "$out/live_urls.txt"

rm -rf "$out/synthetic"
cp -R "$here/../../test/corpus/synthetic" "$out/synthetic"

python3 -I "$here/classify.py" "$out" "$out/classified.json"
python3 -I "$here/expected.py" "$out" "$out/classified.json" "$out/expected.json"
