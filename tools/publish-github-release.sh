#!/usr/bin/env bash
set -euo pipefail

: "${TAG:?}" "${VERSION:?}" "${CHANNEL:?}" "${ARCHIVE:?}" "${SIDECAR:?}"
: "${NOTES:?}" "${REPOSITORY:?}" "${COMMIT:?}"

remote_tag="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"
peeled="$(git ls-remote --tags origin "refs/tags/$TAG^{}" | awk '{print $1}')"
if [[ -n "$remote_tag" ]]; then
  [[ -n "$peeled" && "$peeled" == "$COMMIT" ]] ||
    { echo "Existing tag $TAG is not an annotated tag for $COMMIT." >&2; exit 1; }
else
  git tag -a "$TAG" "$COMMIT" -m "Release $TAG"
  git push origin "refs/tags/$TAG"
fi

release_json="$(mktemp)"
if gh api "repos/$REPOSITORY/releases/tags/$TAG" >"$release_json" 2>/dev/null; then
  [[ "$(jq -r .draft "$release_json")" == "true" ]] ||
    { echo "Published release $TAG will not be modified." >&2; exit 1; }
else
  gh release create "$TAG" --draft --verify-tag \
    --title "Smartmeter V$VERSION" --notes-file "$NOTES"
  gh api "repos/$REPOSITORY/releases/tags/$TAG" >"$release_json"
fi

expected_names="$(printf '%s\n%s\n' "$(basename "$ARCHIVE")" "$(basename "$SIDECAR")" | sort)"
actual_names="$(jq -r '.assets[].name' "$release_json" | sort)"
[[ -z "$(comm -13 <(printf '%s\n' "$expected_names") <(printf '%s\n' "$actual_names"))" ]] ||
  { echo "Draft release contains unexpected assets." >&2; exit 1; }

for asset in "$ARCHIVE" "$SIDECAR"; do
  name="$(basename "$asset")"
  asset_id="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .id' "$release_json")"
  if [[ -z "$asset_id" ]]; then
    gh release upload "$TAG" "$asset"
  else
    downloaded="$(mktemp)"
    gh api -H "Accept: application/octet-stream" \
      "repos/$REPOSITORY/releases/assets/$asset_id" >"$downloaded"
    [[ "$(sha256sum "$downloaded" | awk '{print $1}')" == "$(sha256sum "$asset" | awk '{print $1}')" ]] ||
      { echo "Existing draft asset $name has different bytes." >&2; exit 1; }
  fi
done

gh api "repos/$REPOSITORY/releases/tags/$TAG" >"$release_json"
for asset in "$ARCHIVE" "$SIDECAR"; do
  name="$(basename "$asset")"
  asset_id="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .id' "$release_json")"
  [[ -n "$asset_id" ]] || { echo "Missing uploaded asset $name." >&2; exit 1; }
  downloaded="$(mktemp)"
  gh api -H "Accept: application/octet-stream" \
    "repos/$REPOSITORY/releases/assets/$asset_id" >"$downloaded"
  [[ "$(sha256sum "$downloaded" | awk '{print $1}')" == "$(sha256sum "$asset" | awk '{print $1}')" ]] ||
    { echo "Uploaded asset $name failed hash verification." >&2; exit 1; }
done

release_id="$(jq -r .id "$release_json")"
if [[ "$CHANNEL" == "prerelease" ]]; then
  gh api --method PATCH "repos/$REPOSITORY/releases/$release_id" \
    -F draft=false -F prerelease=true -f make_latest=false >/dev/null
else
  gh api --method PATCH "repos/$REPOSITORY/releases/$release_id" \
    -F draft=false -F prerelease=false -f make_latest=true >/dev/null
fi
