from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CandidateCorePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.core = Path(self.temp.name) / 'core'
        self.core.mkdir()
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        for name in ['Cargo.lock','crates/xray-ffi/include/xray_ffi.h','crates/xray-ffi/include/module.modulemap']:
            p=self.core/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'fixture')
        self.commit=self.git('rev-parse','HEAD')
        self.tree=self.git('rev-parse','HEAD^{tree}')
        self.git('tag','-a','v0.7.0-rc.1','-m','fixture')
        self.tag_object=self.git('rev-parse','v0.7.0-rc.1^{tag}')

    def git(self,*args):
        return subprocess.check_output(['git','-C',str(self.core),*args],text=True).strip()

    def check(self,kind='commit',tag='',object_id='',action='verify_core_checkout "$core_test_dir"'):
        digest=hashlib.sha256(b'fixture\n').hexdigest()
        # All interpolated fields are controlled fixture hex hashes/enum values.
        script='source "$1"; core_test_dir="$2"; '+f'''
XRAY_MOBILE_VERSION=0.7.0-rc.1
XRAY_RUST_REF_KIND={kind}
XRAY_RUST_TAG={tag}
XRAY_RUST_TAG_OBJECT={object_id}
XRAY_RUST_COMMIT={self.commit}
XRAY_RUST_TREE={self.tree}
XRAY_RUST_CARGO_LOCK_SHA256={digest}
XRAY_RUST_FFI_HEADER_SHA256={digest}
XRAY_RUST_MODULEMAP_SHA256={digest}
'''+action
        return subprocess.run(['bash','-c',script,'test',str(ROOT/'scripts/_common.sh'),str(self.core)],capture_output=True,text=True)

    def test_exact_clean_commit_can_be_used_for_candidate_builds(self):
        r=self.check();self.assertEqual(r.returncode,0,r.stderr)

    def test_candidate_does_not_claim_tag_and_cannot_publish(self):
        r=self.check(tag='v0.7.0-rc.1',object_id=self.tag_object)
        self.assertNotEqual(r.returncode,0);self.assertIn('must not claim',r.stderr)
        r=self.check(action='require_tagged_core')
        self.assertNotEqual(r.returncode,0);self.assertIn('publication requires',r.stderr)

    def test_matching_tag_is_still_verified(self):
        r=self.check(kind='tag',tag='v0.7.0-rc.1',object_id=self.tag_object,action='verify_core_checkout "$core_test_dir"; require_tagged_core')
        self.assertEqual(r.returncode,0,r.stderr)
        r=self.check(kind='tag',tag='v0.7.0-rc.1',object_id='0'*40)
        self.assertNotEqual(r.returncode,0);self.assertIn('tag object',r.stderr)

    def test_old_core_tag_cannot_satisfy_new_mobile_publication(self):
        r=self.check(kind='tag',tag='v0.6.1-rc.1',object_id=self.tag_object,action='require_tagged_core')
        self.assertNotEqual(r.returncode,0);self.assertIn('match the mobile version',r.stderr)

    def test_dirty_or_wrong_commit_is_rejected_in_candidate_mode(self):
        (self.core/'untracked.rs').write_text('extra\n')
        r=self.check();self.assertNotEqual(r.returncode,0);self.assertIn('tracked or untracked',r.stderr)
        r=self.check(action='XRAY_RUST_COMMIT='+('0'*40)+'; verify_core_checkout "$core_test_dir"')
        self.assertNotEqual(r.returncode,0);self.assertIn('core checkout is',r.stderr)

    def test_unknown_pin_mode_fails_closed(self):
        r=self.check(kind='branch');self.assertNotEqual(r.returncode,0);self.assertIn('unsupported core reference',r.stderr)


class VersionedEvidenceRunTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);(self.root/'scripts').mkdir();(self.root/'release').mkdir();(self.root/'bin').mkdir()
        for name in ['_common.sh','verify-core-release-evidence-run.sh','release-evidence-profile.sh']:
            shutil.copy2(ROOT/'scripts'/name,self.root/'scripts'/name)
        (self.root/'release/version.env').write_text('XRAY_MOBILE_VERSION=0.7.0-rc.1\n')
        (self.root/'release/core.env').write_text('XRAY_RUST_REPOSITORY=https://github.com/example/core.git\nXRAY_RUST_REF_KIND=tag\nXRAY_RUST_TAG=v0.7.0-rc.1\nXRAY_RUST_TAG_OBJECT='+('3'*40)+'\nXRAY_RUST_COMMIT='+('1'*40)+'\nXRAY_RUST_TREE='+('2'*40)+'\n')
        for name in ['toolchains.env','artifacts.env']:(self.root/'release'/name).write_text('')
        mock=self.root/'bin/gh'
        mock.write_text('''#!/usr/bin/env python3
import os,sys
url=sys.argv[2]
if '/workflows/' in url and 'v07-release-evidence.yml' not in url: sys.exit(9)
if '/workflows/' in url and '/runs?' not in url:
 print('42\\t.github/workflows/v07-release-evidence.yml\\tactive')
elif '/runs?' in url: print('123')
elif '/artifacts?' in url:
 if os.environ.get('CASE')!='expired':print('v07-release-evidence-'+('1'*40)+'\\t'+('1'*40))
elif url.endswith('/runs/123'):
 tree=('4' if os.environ.get('CASE')=='wrong-tree' else '2')*40
 print('42\\t'+('1'*40)+'\\t'+tree+'\\texample/core\\tworkflow_dispatch\\tcompleted\\tsuccess')
else:sys.exit(8)
''');mock.chmod(0o755)

    def run_verifier(self,case='valid'):
        env=dict(os.environ,PATH=str(self.root/'bin')+os.pathsep+os.environ['PATH'],CASE=case)
        return subprocess.run(['bash',str(self.root/'scripts/verify-core-release-evidence-run.sh')],env=env,capture_output=True,text=True)

    def test_v07_queries_its_own_workflow_and_exact_identity(self):
        r=self.run_verifier();self.assertEqual(r.returncode,0,r.stderr)

    def test_wrong_tree_and_missing_live_artifact_are_rejected(self):
        for case in ['wrong-tree','expired']:
            with self.subTest(case=case):self.assertNotEqual(self.run_verifier(case).returncode,0)


if __name__=='__main__':unittest.main()
