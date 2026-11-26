import unittest

from update import DOWNLOAD_ROOT, newest_stable, select_asset, source_pin, update_pin

DIGEST = "a" * 64


def release(tag, *, draft=False, prerelease=False):
    return {"tag_name": tag, "draft": draft, "prerelease": prerelease}


def asset(tag, filename):
    return {
        "name": filename,
        "state": "uploaded",
        "browser_download_url": f"{DOWNLOAD_ROOT}{tag}/{filename}",
        "digest": f"sha256:{DIGEST}",
    }


class ResolverTests(unittest.TestCase):
    def test_select_latest_stable_numerically(self):
        releases = [
            release("v2026.3"),
            release("v2027.1", draft=True),
            release("v2026.10"),
            release("v2026.11-rc1", prerelease=True),
            release("v2022.3.0.1"),
        ]
        self.assertEqual(newest_stable(releases)["tag_name"], "v2026.10")
        self.assertEqual(newest_stable(releases, "v2026.3")["tag_name"], "v2026.3")

    def test_copy_actual_uploaded_url(self):
        tag = "v2026.3"
        archive = asset(tag, "ovms_ubuntu24_2026.3.0_python_off.tar.gz")
        assets = [
            asset(tag, "ovms_ubuntu24_2026.3.0_python_on.tar.gz"),
            asset(tag, archive["name"] + ".sha256"),
            asset(tag, "ovms_ubuntu22_2026.3.0_python_off.tar.gz"),
            archive,
        ]
        self.assertEqual(select_asset(tag, assets, "off"), (archive["browser_download_url"], DIGEST))

    def test_missing_ambiguous_or_unhashed_archive_fails(self):
        tag = "v2026.3"
        archive = asset(tag, "ovms_ubuntu24_2026.3.0_python_off.tar.gz")
        unversioned = asset(tag, "ovms_ubuntu24_python_off.tar.gz")
        for assets in ([], [archive, unversioned], [dict(archive, digest=None)]):
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                select_asset(tag, assets, "off")

    def test_conditional_unversioned_pin_preserves_arm_source_and_comments(self):
        old_url = DOWNLOAD_ROOT + "v2026.0/ovms_ubuntu24_python_on.tar.gz"
        new_url = DOWNLOAD_ROOT + "v2026.1/ovms_ubuntu24_2026.1.0_python_on.tar.gz"
        text = f"""parts:
  openvino-model-server:
    plugin: dump
    source:
      - on amd64: '{old_url}' # preserve this
      - on arm64: snap/local/nil-source
"""
        pin = source_pin(text)
        self.assertEqual(pin[-1], "v2026.0")
        changed = update_pin(text, pin, new_url, DIGEST)
        self.assertEqual(
            changed,
            text.replace(f"'{old_url}'", f"'{new_url}'").replace(
                "    source:\n",
                f"    source-checksum:\n      - on amd64: sha256/{DIGEST}\n    source:\n",
            ),
        )
        self.assertEqual(update_pin(changed, source_pin(changed), new_url, DIGEST), changed)

    def test_scalar_pin_updates_existing_checksum_without_reformatting(self):
        old_url = DOWNLOAD_ROOT + "v2026.2/ovms_ubuntu24_2026.2.0_python_off.tar.gz"
        new_url = DOWNLOAD_ROOT + "v2026.3/ovms_ubuntu24_2026.3.0_python_off.tar.gz"
        text = (
            "parts:\r\n  openvino-model-server:\r\n"
            f"    source: {old_url}\r\n    source-checksum: sha256/{'b' * 64} # pin\r\n"
        )
        self.assertEqual(
            update_pin(text, source_pin(text), new_url, DIGEST),
            text.replace(old_url, new_url).replace("b" * 64, DIGEST),
        )
