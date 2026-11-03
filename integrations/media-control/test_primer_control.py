import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('primer',Path(__file__).with_name('primer-control.py'))
app=importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)

class PrimerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.rootpatch=patch.object(app,'ROOT',self.root);self.rootpatch.start();self.addCleanup(self.rootpatch.stop)
        (self.root/'state/history').mkdir(parents=True)
        (self.root/'run').mkdir()
        self.record=self.root/'state/history/test.json'
        self.record.write_text(json.dumps({'result':'success','log_file':str(self.root/'state/history/test.log')}))

    def test_rejects_shell_and_path_input(self):
        with patch.object(app,'system') as system:
            for command in ['id','run; id','log ../../auth','retry test;id','run now','log /etc/passwd']:
                with self.assertRaises(ValueError):app.main(command)
            system.assert_not_called()

    def test_retry_success_rejected_and_busy_not_queued(self):
        with patch.object(app,'system') as system:
            with self.assertRaises(ValueError):app.trigger('test')
            with patch.object(app,'running',return_value=True):self.assertFalse(app.trigger()['accepted'])
            system.assert_not_called()
            with patch.object(app,'running',return_value=False):self.assertTrue(app.trigger()['accepted'])
            system.assert_called_once_with('systemctl','start','--no-block','codex-primer@manual.service')

    def test_schedule_only_changes_fixed_timer(self):
        for command,operation in [('schedule on','enable'),('schedule off','disable')]:
            with patch.object(app,'system') as system,patch.object(app,'status',return_value={'running':True}):
                value=app.main(command)
                self.assertTrue(value['running'])
                system.assert_called_once_with('systemctl',operation,'--now','codex-primer.timer')

    def test_invalid_schedule_commands_have_no_effect(self):
        with patch.object(app,'system') as system:
            for command in ['schedule','schedule false','schedule on;id','schedule on extra','schedule ../off']:
                with self.assertRaises(ValueError):app.main(command)
            system.assert_not_called()

    def test_logs_confined_and_redacted(self):
        (self.root/'state/history/test.log').write_text('Bearer secret-token-value\nsk-verylongsecretvaluethatmusthide\nOK')
        self.assertIn('OK',app.logs('test')['log'])
        self.assertNotIn('secret-token-value',app.logs('test')['log'])
        outside=self.root/'private.log';outside.write_text('PRIVATE')
        self.record.write_text(json.dumps({'result':'failure','log_file':str(outside)}))
        self.assertNotIn('PRIVATE',app.logs('test')['log'])

if __name__=='__main__':unittest.main()
