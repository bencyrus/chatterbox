#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/secrets/.env.scripts"

[[ -f "${ENV_FILE}" ]] || { echo "Error: secrets/.env.scripts not found" >&2; exit 1; }
set -a; . "${ENV_FILE}"; set +a

OPEN_FLAG="false"
[[ "${1:-}" == "--open" ]] && OPEN_FLAG="true"

[[ -n "${OPENAPI_URL:-}" ]] || { echo "Error: OPENAPI_URL missing in secrets/.env.scripts" >&2; exit 1; }

JSON_TMP="$(mktemp -t openapi.XXXXXX.json)"
DOCS_DIR="${REPO_ROOT}/api_docs"
JSON_OUT="${DOCS_DIR}/api.json"
MD_OUT="${DOCS_DIR}/api.md"

mkdir -p "${DOCS_DIR}"

if ! curl -fsSL "${OPENAPI_URL}" -o "${JSON_TMP}"; then
  echo "Error: failed to fetch OpenAPI from ${OPENAPI_URL}" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  jq -S . "${JSON_TMP}" > "${JSON_OUT}"
else
  if perl -MJSON::PP -e 'exit 0' >/dev/null 2>&1; then
    perl -MJSON::PP -0777 -e 'use JSON::PP qw(decode_json); my $s=do{local $/; <>}; my $d=decode_json($s); print JSON::PP->new->canonical->pretty->encode($d);' "${JSON_TMP}" > "${JSON_OUT}"
  else
    cp "${JSON_TMP}" "${JSON_OUT}"
  fi
fi

# Build api.md with method, path, and inline input shape (properties with required tags)
if command -v jq >/dev/null 2>&1; then
  jq -r '
    def ref_name: split("/") | last;
    def deref($doc; s): if s|has("$ref") then ($doc.definitions[(s["$ref"]|ref_name)] // {}) else s end;
    def shape_block($schema):
      ($schema.properties // {}) as $props | ($schema.required // []) as $req |
      if ($props|length)==0 then "  - input shape: none"
      else
        "  - input shape:\n" + (
          $props | to_entries | sort_by(.key) | map(
            . as $e |
            "    - " + $e.key + ": " + (($e.value.type // "object"))
            + (if (($e.value.format // "") != "") then " (" + ($e.value.format) + ")" else "" end)
            + (if ($req | index($e.key)) then " (required)" else "" end)
          ) | join("\n")
        )
      end;

    . as $doc | ($doc.paths // {}) | to_entries[] as $p |
    $p.value | to_entries[] | select(.key|test("^(get|post|put|delete|patch|options|head)$")) as $m |
    ($m.value.parameters // []) | map(select(.in=="body")) | .[0] as $body |
    if $body == null then "- " + ($m.key|ascii_upcase) + " " + $p.key + "\n  - input: none\n"
    else
      ($body.schema // {}) as $raw | (deref($doc; $raw)) as $schema |
      "- " + ($m.key|ascii_upcase) + " " + $p.key + "\n" + shape_block($schema) + "\n"
    end
  ' "${JSON_TMP}" | sed '1s/^/## API Endpoints (basic)\n\n/' > "${MD_OUT}"
else
  if perl -MJSON::PP -e 'exit 0' >/dev/null 2>&1; then
    perl -MJSON::PP - "$JSON_TMP" > "$MD_OUT" <<'PERL'
use strict; use warnings;
use JSON::PP qw(decode_json);
my $file = shift @ARGV;
open my $fh, '<', $file or die $!;
local $/; my $s = <$fh>;
my $doc = decode_json($s);
my $paths = $doc->{paths} || {};
my @methods = qw(get post put delete patch options head);
print "## API Endpoints (basic)\n\n";
for my $path (sort keys %$paths) {
  my $obj = $paths->{$path} || {};
  for my $m (@methods) {
    next unless exists $obj->{$m};
    my $op = $obj->{$m};
    my $body;
    for my $p (@{ $op->{parameters} || [] }) { if (($p->{in}||"") eq "body") { $body = $p; last; } }
    print "- " . uc($m) . " $path\n";
    if (!$body) { print "  - input: none\n\n"; next; }
    my $schema = $body->{schema} || {};
    if (!$schema->{type} && $schema->{'$ref'}) {
      (my $name = $schema->{'$ref'}) =~ s!.*/!!;
      $schema = $doc->{definitions}{$name} || {};
    }
    my $props = $schema->{properties} || {};
    my @req = @{ $schema->{required} || [] };
    my %is_req = map { $_ => 1 } @req;
    my @keys = sort keys %$props;
    if (@keys) {
      print "  - input shape:\n";
      for my $k (@keys) {
        my $pt = $props->{$k}{type} || 'object';
        my $fmt = $props->{$k}{format} || '';
        my $extra = $fmt ? " ($fmt)" : '';
        my $req_tag = $is_req{$k} ? " (required)" : '';
        print "    - $k: $pt$extra$req_tag\n";
      }
    } else {
      print "  - input shape: none\n";
    }
    print "\n";
  }
}
PERL
  else
    printf "## API Endpoints (basic)\n\n- Unable to parse spec without jq or Perl JSON::PP\n" > "${MD_OUT}"
  fi
fi

rm -f "${JSON_TMP}"

echo "${JSON_OUT}\n${MD_OUT}"

if [[ "${OPEN_FLAG}" == "true" ]] && command -v open >/dev/null 2>&1; then
  if [[ -d "/Applications/Cursor.app" ]] ; then
    open -a "Cursor" "${JSON_OUT}" || open "${JSON_OUT}" || true
  else
    open "${JSON_OUT}" || true
  fi
fi


