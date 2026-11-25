#!/bin/bash -eu

if [ "${TEST_IMAGE_PROMPT:-}" != "true" ]; then
  echo "TEST_IMAGE_PROMPT is not true; skipping vlm test"
  return 0
fi

echo "::group::Getting model name"

status_json=$(_run "$SNAP_NAME" status --format=json)
api_url=$(echo "$status_json" | jq -r '.entrypoints.openai.url // empty')
if [ -z "$api_url" ]; then
  echo "::error::OpenAI entrypoint URL not found in status"
  echo "$status_json"
  exit 1
fi
echo "API URL: $api_url"

# Retry model lookup in a loop, as server might not be ready
max_retries=20
retry_delay=30

retry_count=0
success=false

while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
  set +e
  models_result=$(_run curl "$api_url"/models)
  exit_code=$?
  set -e

  if [ $exit_code -ne 0 ]; then
    echo "Failed to look up models (attempt $((retry_count + 1))/$max_retries)"
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $retry_delay
      continue
    else
      echo "Get logs"
      _run sudo snap logs "$SNAP_NAME" -n 1000
      echo "::error::Failed to look up models: $models_result"
      echo "::endgroup::"
      exit 1
    fi
  fi

  set +e
  model_name=$(echo "$models_result" | jq -r '.data[0].id | if . == null then error("id field not set") else . end')
  exit_code=$?
  set -e

  echo "Model name: $model_name"

  if [ $exit_code -ne 0 ] || [ -z "$model_name" ]; then
    echo "Failed to look up model name (attempt $((retry_count + 1))/$max_retries)"
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $retry_delay
      continue
    else
      echo "Get logs"
      _run sudo snap logs "$SNAP_NAME" -n 1000
      echo "::error::Failed to look up model name: $models_result"
      echo "::endgroup::"
      exit 1
    fi
  fi

  success=true
done

echo "::endgroup::"

echo "::group::Prompting model"

image_data=$(base64 <"$1" | tr -d '\n')

payload="{
  \"model\": \"$model_name\",
  \"messages\": [
    {
      \"role\": \"user\",
      \"content\": [
        {
          \"type\": \"image_url\",
          \"image_url\": {
            \"url\": \"data:image/jpeg;base64,${image_data}\"
          }
        },
        {
          \"type\": \"text\",
          \"text\": \"what is in this image\"
        }
      ]
    }
  ],
  \"max_tokens\": 300,
  \"chat_template_kwargs\": {
    \"enable_thinking\": false
  }
}"

# The _run macro has issues handling quotes and newlines. To work around this we add the
# curl command and its parameters to a script, upload the script to the DUT, and then execute
# this script with the _run command.
echo "#!/bin/bash -eux" >dut-script.sh
echo "curl $api_url/chat/completions -H 'Content-Type: application/json' -d '$payload'" >>dut-script.sh
chmod +x dut-script.sh
_put dut-script.sh :

# Retry prompting in a loop, as server might not be ready for inferencing
retry_count=0
success=false

while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do

  set +e
  response=$(_run ./dut-script.sh)
  exit_code=$?
  set -e

  if [ $exit_code -ne 0 ]; then
    echo "Failed to prompt model (attempt $((retry_count + 1))/$max_retries)"
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $retry_delay
      continue
    else
      echo "Get logs"
      _run sudo snap logs "$SNAP_NAME" -n 1000
      echo "::error::Failed to prompt model: $models_result"
      echo "::endgroup::"
      exit 1
    fi
  fi

  echo "Response: $response"

  # Validate response is valid JSON
  if ! echo "$response" | jq empty 2>/dev/null; then
    echo "Failed to validate response as JSON (attempt $((retry_count + 1))/$max_retries)"
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $retry_delay
      continue
    else
      echo "Get logs"
      _run sudo snap logs "$SNAP_NAME" -n 1000
      echo "::error::Response is not valid JSON: $response"
      echo "::endgroup::"
      exit 1
    fi
  fi

  set +e
  response_content=$(echo "$response" | jq -r '.choices[0].message.content | if . == null then error("content field not set") else . end')
  exit_code=$?
  set -e

  if [ $exit_code -ne 0 ] || [ -z ${#response_content} ]; then
    echo "Failed to extract response content (attempt $((retry_count + 1))/$max_retries)"
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      sleep $retry_delay
      continue
    else
      echo "Get logs"
      _run sudo snap logs "$SNAP_NAME" -n 1000
      echo "::error::Response message empty: $response"
      echo "::endgroup::"
      exit 1
    fi
  fi

  # Prompting model was successful, but still need to validate the response
  success=true
done

# Convert response to lower case and check if it contains the word "circle"
if [[ "${response_content,,}" != *circle* ]]; then
  echo "Get logs"
  _run sudo snap logs "$SNAP_NAME" -n 1000
  echo "::notice::Response does not contain the word 'circle' $response_content"
  echo "$response"
  echo "::endgroup::"
  exit 1
fi

echo "Response contains expected content"

echo "::endgroup::"
