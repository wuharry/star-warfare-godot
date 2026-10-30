"""Read-only parity check: runtime rows == audit JSON == source binary."""
from __future__ import annotations

import hashlib
import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from extract_unity_tables import read_tables


class SoloDataTest(unittest.TestCase):
    def test_every_source_row(self) -> None:
        binary = ROOT / "assets/starwarfare_data/resDataSets_raw.bin"
        source = read_tables(binary)
        audit = json.loads((ROOT / "docs/data/recovered_data_v1/tables.json").read_text())
        generated = (ROOT / "scripts/core/solo_wave_data.gd").read_text()
        match = re.search(r"const TABLES := (\[[\s\S]*\])", generated)
        self.assertIsNotNone(match)
        payload = re.sub(r"#[^\n]*", "", match[1])
        runtime = json.loads(re.sub(r",\s*\]", "]", payload))
        self.assertEqual(len(runtime), 48)
        digest = hashlib.sha256(binary.read_bytes()).hexdigest()
        self.assertEqual(audit["source_sha256"], digest)
        self.assertIn(digest, generated)
        audit_tables = {table["index"]: table["data"] for table in audit["tables"]}
        for index in range(19, 67):
            rows = source[index].decoded_rows()
            self.assertEqual(len(runtime[index - 19]), len(rows), f"table {index} shape")
            for row_index, row in enumerate(rows):
                with self.subTest(table=index, row=row_index):
                    self.assertEqual(runtime[index - 19][row_index], row)
                    self.assertEqual(audit_tables[index][row_index], row)
                    self.assertEqual(len(row), 8)
        self.assertEqual(len(runtime[0]), 11)
        self.assertEqual(sum(row[2] + row[4] + row[6] for row in runtime[0]), 35)
        print("SOLO_DATA_PARITY_PASS tables=48 rows=%d binary=json=runtime" % sum(map(len, runtime)))


if __name__ == "__main__":
    unittest.main()
