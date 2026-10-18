"""Checks for accidental command contract drift."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import protocol_codegen as generator


class ContractGenerationTests(unittest.TestCase):
    def test_invalid_contracts_are_rejected_before_generation(self):
        original = generator.load_schema()
        for mutation in ("duplicate", "owner", "field", "version"):
            schema = copy.deepcopy(original)
            if mutation == "duplicate":
                schema["commands"].insert(0, schema["commands"][0])
            elif mutation == "owner":
                schema["commands"][0]["owner"] = "platform"
            elif mutation == "field":
                schema["commands"][0]["required"] = {"id": "anything"}
            else:
                schema["version"] = True
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / "commands.json"
                path.write_text(json.dumps(schema))
                with self.assertRaises(ValueError):
                    generator.load_schema(path)

    def test_core_and_bridge_ownership_generate_distinct_dispatchers(self):
        schema = generator.load_schema()
        rust, dart = generator.rust_source(schema), generator.dart_source(schema)
        self.assertIn('"session.start" => Self::SessionStart', rust)
        self.assertNotIn('"documents.importFiles" =>', rust)
        self.assertIn('documentsImportFiles("documents.importFiles", core: false)', dart)


if __name__ == "__main__":
    unittest.main()
