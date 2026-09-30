"""Exercise hook commands and integrity guards without launching either agent."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / '.harness'))
spec = importlib.util.spec_from_file_location('claude_hook', ROOT / '.harness/claude_hook.py')
HOOK = importlib.util.module_from_spec(spec)
spec.loader.exec_module(HOOK)


class ClaudeHookTests(unittest.TestCase):
    def test_managed_files_use_lf_without_changing_lock_hashes(self):
        names = list(json.loads((ROOT / '.harness/lock.json').read_text(encoding='utf-8'))['files'])
        result = subprocess.run(['git', 'check-attr', '-z', 'eol', '--', *names],
                                cwd=ROOT, capture_output=True, check=True)
        fields = result.stdout.decode('utf-8').rstrip('\0').split('\0')
        self.assertEqual(fields[2::3], ['lf'] * len(names))
        self.assertEqual(HOOK.integrity(ROOT), [])

    def test_configured_commands_receive_events(self):
        bash = shutil.which('bash')
        if not bash and os.name == 'nt':
            candidate = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe'
            if candidate.is_file():
                bash = str(candidate)
        if not bash:
            self.skipTest('Bash unavailable: configured shell commands NOT RUN')
        cases = [
            ({'hook_event_name': 'UserPromptSubmit', 'prompt': '骨架'}, 'context'),
            ({'hook_event_name': 'PreToolUse', 'tool_name': 'Read',
              'tool_input': {'file_path': '.env'}}, 'deny'),
            ({'hook_event_name': 'PreToolUse', 'tool_name': 'Write',
              'tool_input': {'file_path': 'scripts/example.gd.uid'}}, 'deny'),
            ({'hook_event_name': 'PreToolUse', 'tool_name': 'Read',
              'tool_input': {'file_path': 'README.zh-TW.md'}}, 'empty'),
            ({'hook_event_name': 'PostToolUse', 'tool_name': 'Edit',
              'tool_input': {'file_path': 'scripts/example.gd'}}, 'context'),
            ({'hook_event_name': 'Stop', 'stop_hook_active': False}, 'empty'),
        ]
        for settings in ('.claude/settings.json', '.codex/hooks.json'):
            hooks = json.loads((ROOT / settings).read_text(encoding='utf-8'))['hooks']
            for payload, expected in cases:
                event = payload['hook_event_name']
                command = hooks[event][0]['hooks'][0]['command']
                with self.subTest(settings=settings, event=event, expected=expected):
                    env = dict(os.environ, CLAUDE_PROJECT_DIR=ROOT.as_posix())
                    if settings.startswith('.codex/'):
                        env.pop('CLAUDE_PROJECT_DIR')
                    result = subprocess.run([bash, '--noprofile', '--norc', '-c', command],
                                            cwd=ROOT, env=env, input=json.dumps(dict(payload, cwd=str(ROOT))),
                                            capture_output=True, text=True, encoding='utf-8', timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr, '')
                    output = json.loads(result.stdout) if result.stdout.strip() else None
                    if expected == 'empty':
                        self.assertIsNone(output)
                    elif expected == 'deny':
                        self.assertEqual(output['hookSpecificOutput']['permissionDecision'], 'deny')
                    else:
                        self.assertTrue(output['hookSpecificOutput']['additionalContext'])

    def test_stop_still_blocks_real_drift_and_stops_recursion(self):
        with tempfile.TemporaryDirectory(prefix='claude hook guard ') as tmp:
            root = Path(tmp)
            (root / '.harness').mkdir()
            (root / '.harness/project.json').write_text('{}', encoding='utf-8')
            (root / 'managed.txt').write_bytes(b'original\n')
            lock = {'files': {'managed.txt': hashlib.sha256(b'original\n').hexdigest()}}
            (root / '.harness/lock.json').write_text(json.dumps(lock), encoding='utf-8')
            self.assertIsNone(HOOK.handle({'hook_event_name': 'Stop'}, root))
            (root / 'managed.txt').write_bytes(b'changed\n')
            result = HOOK.handle({'hook_event_name': 'Stop'}, root)
            self.assertEqual(result['decision'], 'block')
            self.assertIn('managed.txt', result['reason'])
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                result = HOOK.handle({'hook_event_name': 'Stop', 'stop_hook_active': True}, root)
            self.assertIsNone(result)
            self.assertIn('FAIL', errors.getvalue())


if __name__ == '__main__':
    unittest.main()
