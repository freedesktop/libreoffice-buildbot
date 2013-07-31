#!/usr/bin/python3
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


class TestTb3Cli(unittest.TestCase):
    def __resolve_ref(self, refname):
        return self.git('show-ref', refname).split(' ')[0]
    def setUp(self):
        (self.branch, self.platform) = ('master', 'linux')
        os.environ['PATH'] += ':.'
        (self.testdir, self.git) = helpers.createTestRepo()
        self.tb3 = sh.tb3.bake(repo=self.testdir, branch=self.branch, platform=self.platform, builder='testbuilder')
        self.state = tb3.repostate.RepoState(self.platform, self.branch, self.testdir)
        self.head = self.state.get_head()
    def tearDown(self):
        sh.rm('-r', self.testdir)
    def test_sync(self):
        self.tb3(sync=True)
    def test_set_commit_finished_good(self):
        self.tb3(set_commit_finished=self.head, result='good')
        self.tb3(set_commit_finished=self.head, result='good', result_reference='foo')
    def test_set_commit_finished_bad(self):
        self.tb3(set_commit_finished=self.head, result='bad')
        self.tb3(set_commit_finished=self.head, result='bad', result_reference='bar')
    def test_set_commit_running(self):
        self.tb3(set_commit_running=self.head)
        self.tb3(set_commit_running=self.head, estimated_duration=240)
    def test_show_state(self):
        self.tb3(show_state=True)
    def test_show_history(self):
        self.tb3(show_history=True, history_count=5)
    def test_show_proposals(self):
        self.tb3(show_proposals=True)
        self.tb3(show_proposals=True, format='json')

if __name__ == '__main__':
    unittest.main()
# vim: set et sw=4 ts=4:
