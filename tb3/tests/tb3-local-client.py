#!/usr/bin/python
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import sh
import sys
import os
import unittest

sys.path.append('./tests')
import helpers

#only for setup
sys.path.append('./dist-packages')
import tb3.repostate

class TestTb3LocalClient(unittest.TestCase):
    def setUp(self):
        (self.branch, self.platform, self.builder) = ('master', 'linux', 'testbuilder')
        os.environ['PATH'] += ':.'
        (self.testdir, self.git) = helpers.createTestRepo()
        self.tb3localclient = sh.Command.bake(sh.Command("tb3-local-client"),
            repo=self.testdir,
            branch=self.branch,
            platform=self.platform,
            builder=self.builder,
            tb3_master='./tb3',
            script='./tests/build-script.sh',
            count=1)
        self.state = tb3.repostate.RepoState(self.platform, self.branch, self.testdir)
        self.history = tb3.repostate.RepoHistory(self.platform, self.testdir)
        self.head = self.state.get_head()
    def tearDown(self):
        sh.rm('-r', self.testdir)
    def test_sync(self):
        self.tb3localclient()
        self.assertEqual(self.state.get_last_good(), self.head)
        state = self.history.get_commit_state(self.head)
        self.assertEqual(state.state, 'GOOD')
        self.assertEqual(state.builder, self.builder)

if __name__ == '__main__':
    unittest.main()
# vim: set et sw=4 ts=4:
