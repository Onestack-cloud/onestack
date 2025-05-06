#!/usr/bin/env bash
set -euo pipefail

# First, create a processed root.env with placeholders replaced
ROOT_ENV_PROCESSED="root.env.processed"
echo "Processing root.env..."

# Replace all SECRET_KEY_PLACEHOLDER instances with unique keys
perl -pe '
  s/\$\{SECRET_KEY_PLACEHOLDER\}/
    do {
      my $r = `openssl rand -base64 32`;
      chomp $r;
      $r;
    }
  /ge
' "root.env" > "$ROOT_ENV_PROCESSED"

# Now source the processed file
set -a
source "$ROOT_ENV_PROCESSED"
set +a

# Process each subdirectory template.env
for dir in */; do
  template_file="$dir/template.env"
  output_file="$dir/.env"
  if [[ -f "$template_file" ]]; then
    echo "Generating $output_file from $template_file..."

    perl -Mbytes -pe '
      s/\$\{([^}]+)\}/
        exists $ENV{$1}
          ? $ENV{$1}
          : do {
              my $r = `openssl rand -base64 32`;
              chomp $r;
              $r;
            }
      /ge
    ' "$template_file" > "$output_file"
  fi
done

# Clean up
rm "$ROOT_ENV_PROCESSED"

echo "Done."