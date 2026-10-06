"""The exact historical glTF hash may differ by LF/CRLF, never by content."""
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/armor_runtime_v1"))
import validate_titan_helmet as provenance


class HistoricalTextIdentityTest(unittest.TestCase):
    def setUp(self):
        (ROOT / "test_output").mkdir(exist_ok=True)
        self.folder = tempfile.TemporaryDirectory(dir=ROOT / "test_output")
        self.path = Path(self.folder.name) / "source.gltf"
        self.lf = b'{\n  "name": "ArmorHead_05"\n}\n'
        self.crlf = self.lf.replace(b"\n", b"\r\n")
        self.pin = hashlib.sha256(self.crlf).hexdigest()

    def tearDown(self):
        provenance.HISTORICAL_TEXT_SHA.pop(self.path.resolve(), None)
        self.folder.cleanup()

    def test_pinned_lf_and_crlf_both_match_exact_historical_bytes(self):
        provenance._authorize_text(self.path, self.pin)
        for payload in (self.lf, self.crlf):
            self.path.write_bytes(payload)
            self.assertEqual(provenance.matched_bytes(self.path, self.pin, historical=True), self.crlf)

    def test_unregistered_hash_cannot_use_eol_exception(self):
        self.path.write_bytes(self.lf)
        with self.assertRaises(AssertionError):
            provenance.matched_bytes(self.path, self.pin, historical=True)

    def test_content_change_is_rejected_even_with_registered_pin(self):
        provenance._authorize_text(self.path, self.pin)
        self.path.write_bytes(self.lf.replace(b"ArmorHead_05", b"ArmorHead_06"))
        with self.assertRaises(AssertionError):
            provenance.matched_bytes(self.path, self.pin, historical=True)

    def test_active_files_do_not_use_historical_exception(self):
        provenance._authorize_text(self.path, self.pin)
        self.path.write_bytes(self.lf)
        with self.assertRaises(AssertionError):
            provenance.matched_bytes(self.path, self.pin, historical=False)


if __name__ == "__main__":
    unittest.main()
