#!/usr/bin/env python3
"""Exercise revision guards and release selection without production access."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

DEPLOY = Path(__file__).resolve().parent


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="wanpan-deploy-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("WANPAN_")}
        self.git("init", "-q")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "user.name", "Deployment test")
        self.git("commit", "-qm", "base", "--allow-empty")
        self.base = self.git("rev-parse", "HEAD")
        (self.root / "server").mkdir()
        (self.root / "server/index.ts").write_text("backend v1\n")
        self.git("add", "server")
        self.git("commit", "-qm", "backend", "--allow-empty")
        self.backend = self.git("rev-parse", "HEAD")
        (self.root / "flutter_app").mkdir()
        (self.root / "flutter_app/client.txt").write_text("client v1\n")
        self.git("add", "flutter_app")
        self.git("commit", "-qm", "client", "--allow-empty")
        self.latest = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "--detach", self.base)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, env=self.env, stderr=subprocess.DEVNULL, text=True).strip()

    def select(self, expected="", pinned=False, fetched=None):
        env = dict(self.env, WANPAN_EXPECT_REVISION=expected,
                   WANPAN_ALLOW_ANCESTOR_REVISION="1" if pinned else "0")
        return subprocess.run(
            ["bash", "-ec", 'source "$1"; wanpan_select_revision "$2"', "test",
             str(DEPLOY / "deploy-common.sh"), fetched or self.latest],
            cwd=self.root, env=env, capture_output=True, text=True)

    def test_manual_uses_latest(self):
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.latest)

    def test_manual_bundle_still_requires_latest(self):
        self.assertNotEqual(self.select(self.backend).returncode, 0)

    def test_ci_keeps_exact_bundle_after_client_push(self):
        result = self.select(self.backend, pinned=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.backend)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.base)

    def test_ci_refuses_revision_outside_main(self):
        self.git("commit", "-qm", "unmerged", "--allow-empty")
        unmerged = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "--detach", self.base)
        self.assertNotEqual(self.select(unmerged, pinned=True).returncode, 0)

    def test_ci_refuses_older_deployment(self):
        self.git("checkout", "-q", "--detach", self.latest)
        self.assertNotEqual(self.select(self.backend, pinned=True).returncode, 0)

    def test_same_revision_can_retry(self):
        self.git("checkout", "-q", "--detach", self.backend)
        self.assertEqual(self.select(self.backend, pinned=True).returncode, 0)

    def test_revision_must_be_full_sha(self):
        self.assertNotEqual(self.select("main", pinned=True).returncode, 0)

    def ready(self, branch_head=None):
        result = subprocess.run(
            ["bash", "-ec", 'source "$1"; wanpan_ready_revision "$2"', "test",
             str(DEPLOY / "deploy-common.sh"), branch_head or self.latest],
            cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def mark_ready(self, revision):
        self.git("update-ref", "refs/wanpan-auto-deploy/tags/server-ready-" + revision[:12], revision)

    def test_no_ready_tag_waits(self):
        self.assertEqual(self.ready(), "")

    def test_bundle_tag_alone_does_not_authorize_deployment(self):
        self.git("update-ref", "refs/wanpan-auto-deploy/tags/server-bundle-" + self.backend[:12], self.backend)
        self.assertEqual(self.ready(), "")

    def test_local_ready_tag_does_not_authorize_deployment(self):
        self.git("tag", "server-ready-" + self.backend[:12], self.backend)
        self.assertEqual(self.ready(), "")

    def test_ready_backend_survives_client_only_push(self):
        self.mark_ready(self.backend)
        self.assertEqual(self.ready(), self.backend)

    def test_new_backend_change_waits_for_its_own_ready_tag(self):
        self.mark_ready(self.backend)
        self.git("checkout", "-q", "--detach", self.latest)
        (self.root / "server/index.ts").write_text("backend v2\n")
        self.git("commit", "-qam", "next backend")
        newest = self.git("rev-parse", "HEAD")
        self.assertEqual(self.ready(newest), "")
        self.mark_ready(newest)
        self.assertEqual(self.ready(newest), newest)

    def test_wrong_ready_tag_target_is_ignored(self):
        self.git("update-ref", "refs/wanpan-auto-deploy/tags/server-ready-" + self.backend[:12], self.latest)
        self.assertEqual(self.ready(), "")

    def test_side_branch_ready_tag_cannot_bypass_merged_tests(self):
        self.git("checkout", "-qb", "side", self.base)
        (self.root / "side.txt").write_text("side\n")
        self.git("add", "side.txt")
        self.git("commit", "-qm", "side")
        side = self.git("rev-parse", "HEAD")
        self.mark_ready(side)
        self.git("checkout", "-q", "--detach", self.latest)
        self.git("merge", "--no-ff", "-qm", "merge side", "side")
        merged = self.git("rev-parse", "HEAD")
        self.assertEqual(self.ready(merged), "")
        self.mark_ready(merged)
        self.assertEqual(self.ready(merged), merged)

    @unittest.skipUnless(shutil.which("flock"), "flock is provided by the Linux deployment host")
    def test_deployment_lock_blocks_other_processes(self):
        cmd = ['bash', '-ec', 'source "$1"; wanpan_lock_deployment; echo locked; read -r line',
               'test', str(DEPLOY / 'deploy-common.sh')]
        proc = subprocess.Popen(cmd, cwd=self.root, env=self.env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(proc.stdout.readline().strip(), "locked")
            other = subprocess.run(cmd, cwd=self.root, env=self.env, input="done\n",
                                   capture_output=True, text=True)
            self.assertNotEqual(other.returncode, 0)
        finally:
            proc.communicate("done\n", timeout=5)
        again = subprocess.run(cmd, cwd=self.root, env=self.env, input="done\n",
                               capture_output=True, text=True)
        self.assertEqual(again.returncode, 0, again.stderr)


@unittest.skipUnless(shutil.which("flock"), "poller runs on Linux with flock")
class PollerTests(unittest.TestCase):
    git = DeploymentTests.git

    def setUp(self):
        DeploymentTests.setUp(self)
        self.git("checkout", "-qB", "main", self.latest)
        deploy = self.root / "deploy"
        deploy.mkdir()
        for name in ["auto-deploy.sh", "deploy-common.sh"]:
            shutil.copyfile(DEPLOY / name, deploy / name)
        (deploy / "server-deploy-bundle.sh").write_text('''#!/usr/bin/env bash
set -e
echo attempt >> .deploy/attempts
test "${TEST_DEPLOY_FAIL:-0}" != 1
git merge --ff-only "$WANPAN_EXPECT_REVISION" >/dev/null
printf '%s\\n' "${WANPAN_EXPECT_REVISION:0:12}" > .deploy/current-image-tag
''')
        (self.root / ".gitignore").write_text(".deploy/\n")
        self.git("add", "deploy", ".gitignore")
        self.git("commit", "-qm", "install poller fixture")
        other = tempfile.TemporaryDirectory(prefix="wanpan-poller-checkout-")
        self.addCleanup(other.cleanup)
        self.checkout = Path(other.name) / "checkout"
        subprocess.run(["git", "clone", "-q", "-b", "main", str(self.root), str(self.checkout)], check=True)
        bindir = Path(other.name) / "bin"
        bindir.mkdir()
        curl = bindir / "curl"
        curl.write_text('#!/usr/bin/env bash\necho probe >> .deploy/probes\ntest "${TEST_PUBLIC_FAIL:-0}" != 1\n')
        curl.chmod(0o700)
        self.poll_env = dict(self.env, WANPAN_ROOT=str(self.checkout),
                             PATH=str(bindir) + os.pathsep + self.env["PATH"])

    def poll(self, **settings):
        return subprocess.run(["bash", "deploy/auto-deploy.sh"], cwd=self.checkout,
                              env=dict(self.poll_env, **settings), capture_output=True, text=True)

    def publish(self, version):
        (self.root / "server/index.ts").write_text(version)
        self.git("commit", "-qam", version)
        revision = self.git("rev-parse", "HEAD")
        self.git("tag", "server-ready-" + revision[:12], revision)
        return revision

    def attempts(self):
        path = self.checkout / ".deploy/attempts"
        return len(path.read_text().splitlines()) if path.exists() else 0

    def test_remote_tag_deletion_prunes_mirror_but_preserves_local_tags(self):
        revision = self.publish("ready marker revoked before deployment")
        # Fetch while an invalid target prevents deployment, then remove the
        # remote marker. The next poll must remove the previously mirrored ref.
        tag = "server-ready-" + revision[:12]
        self.git("tag", "-f", tag, self.backend)
        subprocess.run(["git", "tag", tag, "HEAD"], cwd=self.checkout, check=True)
        subprocess.run(["git", "tag", "operator-local", "HEAD"], cwd=self.checkout, check=True)
        result = self.poll()
        self.assertEqual(result.returncode, 0, result.stderr)
        mirror = "refs/wanpan-auto-deploy/tags/" + tag
        self.assertEqual(subprocess.check_output(
            ["git", "rev-parse", "--verify", mirror], cwd=self.checkout, text=True).strip(), self.backend)
        self.git("tag", "-d", tag)
        result = self.poll()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(subprocess.run(
            ["git", "rev-parse", "--verify", mirror], cwd=self.checkout, capture_output=True).returncode, 0)
        for local in [tag, "operator-local"]:
            self.assertEqual(subprocess.run(
                ["git", "rev-parse", "--verify", "refs/tags/" + local],
                cwd=self.checkout, capture_output=True).returncode, 0)
        self.assertEqual(self.attempts(), 0)
        # Reinstating the correct remote marker permits the next poll to deploy.
        self.git("tag", tag, revision)
        result = self.poll()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attempts(), 1)

    def test_poll_fetch_deploy_failure_freeze_and_probe_retry(self):
        # An empty ready-tag namespace must not make git fetch fail.
        result = self.poll()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attempts(), 0)
        first = self.publish("backend first ready")
        (self.root / "flutter_app/client.txt").write_text("new client only")
        self.git("commit", "-qam", "client after ready")
        result = self.poll()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attempts(), 1)
        self.assertEqual((self.checkout / ".deploy/auto-deploy-success-revision").read_text().strip(), first)
        self.assertEqual(self.poll().returncode, 0)
        self.assertEqual(self.attempts(), 1)

        failed = self.publish("backend fails to start")
        self.assertNotEqual(self.poll(TEST_DEPLOY_FAIL="1").returncode, 0)
        self.assertEqual(self.attempts(), 2)
        self.assertEqual((self.checkout / ".deploy/auto-deploy-failed-revision").read_text().strip(), failed)
        self.assertEqual(self.poll().returncode, 0)
        self.assertEqual(self.attempts(), 2)

        fixed = self.publish("backend fixed")
        result = self.poll()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attempts(), 3)
        self.assertEqual((self.checkout / ".deploy/auto-deploy-success-revision").read_text().strip(), fixed)

        self.publish("public check needs retry")
        self.assertNotEqual(self.poll(TEST_PUBLIC_FAIL="1").returncode, 0)
        self.assertEqual(self.attempts(), 4)
        (self.checkout / ".deploy/auto-deploy-failed-revision").unlink()
        self.assertEqual(self.poll().returncode, 0)
        self.assertEqual(self.attempts(), 4)  # Retry probes, not the migration.

        (self.checkout / "server/index.ts").write_text("operator edit")
        self.assertNotEqual(self.poll().returncode, 0)
        self.assertEqual(self.attempts(), 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
