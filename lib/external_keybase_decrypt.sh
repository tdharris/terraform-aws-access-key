#!/bin/bash

# Exit if any of the intermediate steps fail
set -e

# Extract "foo" and "baz" arguments from the input into
# FOO and BAZ shell variables.
# jq will ensure that the values are properly quoted
# and escaped for consumption by the shell.
eval "$(jq -r '@sh "SECRET=\(.encrypted_secret)"')"

# Placeholder for whatever data-fetching logic your script implements
DECRYPTED_SECRET=$(echo "$SECRET" | base64 --decode | keybase pgp decrypt)

# Safely produce a JSON object containing the result value.
# jq will ensure that the value is properly quoted
# and escaped to produce a valid JSON string.
jq -n --arg decrypted_secret "$DECRYPTED_SECRET" '{"decrypted_secret":$decrypted_secret}'
