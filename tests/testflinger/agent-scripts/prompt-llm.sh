#!/bin/bash -eu

if [ "${TEST_CHAT_TPS:-}" != "true" ]; then
  echo "TEST_CHAT_TPS is not true; skipping chat TPS benchmark"
  return 0
fi

echo "::group::Waiting to chat"
max_retries=20
retry_count=0
retry_delay=30
until _run bash -c 'echo "hi" | '"$SNAP_NAME"' chat'; do
  retry_count=$((retry_count + 1))
  if [ $retry_count -ge $max_retries ]; then
    echo "Get logs"
    _run sudo snap logs "$SNAP_NAME" -n 1000
    echo "::error::Machine: $dut_hostname, chat failed to respond after $((max_retries * 30)) seconds"
    echo "::endgroup::"
    exit 1
  fi
  echo "✘ Chat failed, retrying in ${retry_delay}s... ($retry_count/$max_retries)"
  sleep $retry_delay
done
echo "✔ Chat responded"
echo "::endgroup::"

echo "::group::Running benchmark"
_run "git clone --depth 1 --branch v1.0.5 https://github.com/Yoosu-L/llmapibenchmark.git"
status_json=$(_run $SNAP_NAME status --format=json)
api_url=$(echo "$status_json" | jq -r '.entrypoints.openai.url // empty')
if [ -z "$api_url" ]; then
  echo "::error::Machine: $dut_hostname, OpenAI entrypoint URL not found in status"
  echo "$status_json"
  exit 1
fi
echo "API URL: $api_url"
benchmark_result=$(_run "cd llmapibenchmark/cmd && DEBUG=true go run . --base-url=$api_url --concurrency=1 --format=json")
echo "$benchmark_result"

result_tps=$(echo "$benchmark_result" | jq .results[0].generation_speed)
too_low=$(echo "$result_tps < $EXPECTED_TPS" | bc -l)

echo "::notice::Machine: $dut_hostname, Engine: $selected_engine, TPS: $result_tps"

if [ "$too_low" -eq 1 ]; then
  echo "Get logs"
  _run sudo snap logs "$SNAP_NAME" -n 1000
  echo "::error::Machine: $dut_hostname, TPS too low: $result_tps"
  echo "::endgroup::"
  exit 1
fi

echo "::endgroup::"
