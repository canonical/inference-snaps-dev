import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.request import urlopen

import yaml
from yaml.nodes import MappingNode, ScalarNode, SequenceNode

REPO = "openvinotoolkit/model_server"
DOWNLOAD_ROOT = f"https://github.com/{REPO}/releases/download/"
TAG = re.compile(r"v(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?")
PART = "openvino-model-server"
# OVMS's Ubuntu 24 Linux tarballs are for amd64. Other architectures need
# their own explicit asset selection rules, not a fallback to this archive.
SELECTOR = "on amd64"


def version(tag):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError(f"Unrecognized OVMS stable tag: {tag}")
    return tuple(int(component or "0") for component in match.groups())


def github_pages(endpoint):
    result = subprocess.run(
        ["gh", "api", "--paginate", "--jq", ".[]", endpoint],
        check=True,
        capture_output=True,
        text=True,
    )
    return [json.loads(line) for line in result.stdout.splitlines()]


def newest_stable(releases, through=None):
    ceiling = version(through) if through else None
    candidates = []
    for release in releases:
        if release["draft"] or release["prerelease"]:
            continue
        tag = release["tag_name"]
        number = version(tag)
        if ceiling is None or number <= ceiling:
            candidates.append((number, release))
    if not candidates:
        raise ValueError("No stable OVMS releases found within the requested range")
    newest = max(number for number, _ in candidates)
    matches = [release for number, release in candidates if number == newest]
    if len(matches) != 1:
        raise ValueError(f"Ambiguous stable OVMS release tags: {[r['tag_name'] for r in matches]}")
    return matches[0]


def select_asset(tag, assets, variant):
    pattern = re.compile(rf"ovms_ubuntu24_(?:\d+(?:\.\d+)*_)?python_{variant}\.tar\.gz")
    matches = [
        asset
        for asset in assets
        if asset["state"] == "uploaded" and pattern.fullmatch(asset["name"])
    ]
    if len(matches) != 1:
        names = ", ".join(asset["name"] for asset in assets) or "(none)"
        raise ValueError(
            f"{tag}: expected one Ubuntu 24 amd64 python_{variant} archive, "
            f"found {len(matches)}; published assets: {names}"
        )
    asset = matches[0]
    url = asset["browser_download_url"]
    if url != f"{DOWNLOAD_ROOT}{tag}/{asset['name']}":
        raise ValueError(f"{tag}: unexpected download URL for {asset['name']}: {url}")
    digest = asset.get("digest") or ""
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError(f"{tag}: GitHub did not provide a SHA-256 for {asset['name']}")
    return url, digest.removeprefix("sha256:")


def field(node, name, *, required=True):
    if not isinstance(node, MappingNode):
        raise ValueError(f"Expected a mapping containing {name!r}")
    matches = [(key, value) for key, value in node.value if key.value == name]
    if len(matches) > 1 or (required and not matches):
        raise ValueError(f"Expected exactly one {name!r} key")
    return matches[0] if matches else (None, None)


def source_pin(text):
    project = yaml.compose(text, Loader=yaml.BaseLoader)
    _, parts = field(project, "parts")
    _, part = field(parts, PART)
    key, source = field(part, "source")
    conditional = isinstance(source, SequenceNode)
    selected = architecture_value(source, SELECTOR) if conditional else source
    validate_scalar(key, selected)
    match = re.fullmatch(re.escape(DOWNLOAD_ROOT) + r"([^/]+)/[^/\s]+", selected.value)
    if not match:
        raise ValueError(f"{PART} source is not a pinned upstream OVMS download")
    return part, key, selected, conditional, match[1]


def architecture_value(sequence, selector):
    if not isinstance(sequence, SequenceNode):
        raise ValueError(f"Expected architecture-specific values for {selector!r}")
    matches = []
    for entry in sequence.value:
        if isinstance(entry, MappingNode):
            _, value = field(entry, selector, required=False)
            if value is not None:
                matches.append(value)
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one architecture selector {selector!r}")
    return matches[0]


def validate_scalar(key, node):
    if (
        not isinstance(node, ScalarNode)
        or node.start_mark.index < key.end_mark.index
        or node.start_mark.line != node.end_mark.line
        or node.style not in (None, "'", '"')
    ):
        raise ValueError(f"Unsupported YAML value for {key.value!r}")


def scalar_edit(key, node, value):
    validate_scalar(key, node)
    quote = node.style or ""
    return node.start_mark.index, node.end_mark.index, f"{quote}{value}{quote}"


def update_pin(text, pin, url, digest):
    part, source_key, source, conditional, _ = pin
    checksum_key, checksum = field(part, "source-checksum", required=False)
    value = f"sha256/{digest}"
    edits = [scalar_edit(source_key, source, url)]
    if checksum_key is not None:
        if conditional:
            checksum = architecture_value(checksum, SELECTOR)
        edits.append(scalar_edit(checksum_key, checksum, value))
    else:
        if part.flow_style:
            raise ValueError("Cannot insert a checksum into a flow-style OVMS part")
        column = source_key.start_mark.column
        line_start = source_key.start_mark.index - column
        indent = " " * column
        newline = "\r\n" if "\r\n" in text else "\n"
        checksum_line = f"{indent}source-checksum: {value}{newline}"
        if conditional:
            checksum_line = (
                f"{indent}source-checksum:{newline}{indent}  - {SELECTOR}: {value}{newline}"
            )
        edits.append((line_start, line_start, checksum_line))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def verify_download(url, expected_digest):
    with urlopen(url, timeout=60) as response:
        actual = hashlib.file_digest(response, "sha256").hexdigest()
    if actual != expected_digest:
        raise ValueError(f"Downloaded SHA-256 mismatch for {url}: {actual} != {expected_digest}")


def main():
    parser = argparse.ArgumentParser(description="Update the Ubuntu 24 amd64 OVMS pin")
    parser.add_argument("snapcraft_file", type=Path)
    parser.add_argument("--python-variant", required=True, choices=["on", "off"])
    parser.add_argument("--release-through")
    parser.add_argument("--verify-download", action="store_true")
    args = parser.parse_args()
    try:
        text = args.snapcraft_file.read_bytes().decode("utf-8")
        pin = source_pin(text)
        current = pin[-1]
        release = newest_stable(
            github_pages(f"repos/{REPO}/releases?per_page=100"), args.release_through
        )
        tag = release["tag_name"]
        if version(tag) <= version(current):
            print(f"OVMS is already pinned to {current}; no newer candidate ({tag}).")
            return
        assets = github_pages(f"repos/{REPO}/releases/{release['id']}/assets?per_page=100")
        url, digest = select_asset(tag, assets, args.python_variant)
        updated = update_pin(text, pin, url, digest)
        if args.verify_download:
            verify_download(url, digest)
            print(f"Verified the SHA-256 of {url}")
        args.snapcraft_file.write_bytes(updated.encode("utf-8"))
        print(f"OVMS {current} -> {tag}: {url} (sha256/{digest})")
    except subprocess.CalledProcessError as error:
        parser.exit(1, f"OVMS GitHub API request failed: {error.stderr.strip()}\n")
    except (ValueError, KeyError, OSError, yaml.YAMLError) as error:
        parser.exit(1, f"OVMS update failed: {error}\n")


if __name__ == "__main__":
    main()
