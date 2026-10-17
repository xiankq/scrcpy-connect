import argparse
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import android


class ReleaseRegistrationTest(unittest.TestCase):
    def test_stale_integration_registration_is_rejected_before_flutter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'key.properties').touch()
            registrant = root / 'app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
            registrant.parent.mkdir(parents=True)
            registrant.write_text('new dev.flutter.plugins.integration_test.IntegrationTestPlugin()')
            args = argparse.Namespace(mode='release', abi='arm64', no_pub=True)
            with patch.object(android, 'ANDROID', root), patch.object(android, 'run') as run:
                with self.assertRaisesRegex(ValueError, '--no-pub'):
                    android.build_apk(args)
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
