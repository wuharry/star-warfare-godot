"""Regression checks for Unity's same-indent curve lists."""
import unittest

from export import keys, section


class CurveParsingTest(unittest.TestCase):
    def test_section_keeps_same_indent_list(self):
        source = "  m_ScaleCurves:\n  - curve:\n      m_Curve:\n      - time: 0\n        value: 1\n  m_FloatCurves:\n  - curve:\n"
        result = section(source, "m_ScaleCurves", 2)
        self.assertIn("- curve:", result)
        self.assertIn("value: 1", result)
        self.assertNotIn("m_FloatCurves", result)

    def test_keys_preserve_vector_tangents(self):
        result = keys("      - time: 0.25\n        value: {x: 1, y: 2, z: 3}\n        inSlope: {x: 0, y: -2, z: 0}\n        outSlope: {x: 4, y: 0, z: 0}\n")
        self.assertEqual(result, [{"time": 0.25, "value": [1, 2, 3], "in": [0, -2, 0], "out": [4, 0, 0]}])


if __name__ == "__main__":
    unittest.main()
