#!/usr/bin/env python3
"""Exercise the release workflow's real tag/version and green-Build gates."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
workflow = Path(sys.argv[1]) if len(sys.argv) > 1 else root / '.github/workflows/release.yml'
source = workflow.read_text()


def step(name):
    section = source.split(f'      - name: {name}\n', 1)[1]
    block = section.split('        run: |\n', 1)[1].split('\n      - name:', 1)[0]
    return '\n'.join(line[10:] for line in block.splitlines() if line.startswith('          '))


def git(cwd, *args):
    return subprocess.check_output(['git', *args], cwd=cwd, stderr=subprocess.DEVNULL).decode().strip()


with tempfile.TemporaryDirectory(prefix='brev-release-gate-') as temp:
    base = Path(temp)
    origin = base / 'origin'
    origin.mkdir()
    git(origin, 'init', '-b', 'main')
    git(origin, 'config', 'user.name', 'Release gate fixture')
    git(origin, 'config', 'user.email', 'fixture@example.invalid')
    action = origin / '.github/actions/release-signing/action.yml'
    action.parent.mkdir(parents=True)
    action.write_text('tag signing action\n')
    git(origin, 'add', '.github/actions/release-signing/action.yml')
    git(origin, 'commit', '-m', 'Tag source')
    tag_sha = git(origin, 'rev-parse', 'HEAD')
    git(origin, 'tag', 'v0.2.0')
    action.write_text('workflow signing action with widget profile\n')
    git(origin, 'add', '.github/actions/release-signing/action.yml')
    git(origin, 'commit', '-m', 'Updated workflow')
    workflow_sha = git(origin, 'rev-parse', 'HEAD')
    checkout = base / 'checkout'
    git(base, 'clone', str(origin), str(checkout))
    git(checkout, 'checkout', 'refs/tags/v0.2.0')
    git(checkout, 'config', 'user.name', 'Release gate fixture')
    git(checkout, 'config', 'user.email', 'fixture@example.invalid')
    bin_dir = base / 'bin'
    bin_dir.mkdir()
    mock = bin_dir / 'gh'
    mock.write_text('''#!/usr/bin/env python3
import os, sys
commit = sys.argv[sys.argv.index('--commit') + 1]
if commit != os.environ['EXPECTED_TAG_SHA']:
    sys.exit('green Build was queried for workflow HEAD rather than tag HEAD')
print(os.environ.get('FIXTURE_GREEN_COUNT', '1'))
''')
    mock.chmod(0o755)
    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
               BREV_RELEASE_TAG='v0.2.0', GITHUB_REF_NAME='main', GITHUB_SHA=workflow_sha,
               GITHUB_ENV=str(base / 'github-env'), EXPECTED_TAG_SHA=tag_sha,
               SIGNING_WORKFLOW_SHA=workflow_sha, RUNNER_TEMP=str(base))
    resolved = subprocess.run(['bash', '-e', '-c', step('Resolve release version')], cwd=checkout, env=env, capture_output=True)
    assert resolved.returncode == 0, 'manual dispatch must resolve the requested tag, not main'
    assert 'VERSION=0.2.0' in (base / 'github-env').read_text()
    for invalid in ('main', '0.2.0', 'vbad'):
        rejected = subprocess.run(['bash', '-e', '-c', step('Resolve release version')], cwd=checkout,
                                  env=dict(env, BREV_RELEASE_TAG=invalid), capture_output=True)
        assert rejected.returncode != 0, f'invalid tag accepted: {invalid}'
    signing = step('Load signing action from workflow revision')
    loaded = subprocess.run(['bash', '-c', signing], cwd=checkout, env=env, capture_output=True)
    assert loaded.returncode == 0, 'current workflow signing action must load for an older tag'
    assert (checkout / '.github/actions/release-signing/action.yml').read_text() == action.read_text()
    assert git(checkout, 'rev-parse', 'HEAD') == tag_sha, 'release source must stay on the requested tag'
    rejected = subprocess.run(['bash', '-c', signing], cwd=checkout,
                              env=dict(env, SIGNING_WORKFLOW_SHA='invalid'), capture_output=True)
    assert rejected.returncode != 0, 'invalid signing workflow revision accepted'
    gate = step('Gate on main ancestry and green Build')
    passed = subprocess.run(['bash', '-c', gate], cwd=checkout, env=env, capture_output=True)
    assert passed.returncode == 0, 'green Build must be checked for the tag SHA, not workflow SHA'
    missing = subprocess.run(['bash', '-c', gate], cwd=checkout,
                             env=dict(env, FIXTURE_GREEN_COUNT='0'), capture_output=True)
    assert missing.returncode != 0, 'tag without green Build accepted'
    git(checkout, 'checkout', '--orphan', 'off-main')
    git(checkout, 'commit', '--allow-empty', '-m', 'Unrelated source')
    unrelated = subprocess.run(['bash', '-c', gate], cwd=checkout, env=env, capture_output=True)
    assert unrelated.returncode != 0, 'tag source outside main ancestry accepted'
print('release dispatch gates: valid tag SHA accepted; invalid tag, missing Build, and unrelated source rejected')
